import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:orion/widgets/orion_glass.dart';

class _Stripes extends CustomPainter {
  const _Stripes();
  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 8, size.height),
        Paint()
          ..color = (x ~/ 8).isEven
              ? const Color(0xffd0463b)
              : const Color(0xff3588cf),
      );
    }
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}

class _EditorProbe extends StatefulWidget {
  const _EditorProbe({super.key});
  @override
  State<_EditorProbe> createState() => _EditorProbeState();
}

class _EditorProbeState extends State<_EditorProbe> {
  final text = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  int page = 3;
  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Column(
      children: [
        TextField(controller: text, focusNode: focus),
        Expanded(
          child: ListView(
            controller: scroll,
            children: [
              for (var i = 0; i < 12; i++)
                Text('Row $i', style: const TextStyle(height: 2)),
            ],
          ),
        ),
      ],
    ),
  );
}

void main() {
  final capture = GlobalKey();
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(260, 160),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.fromSize(
            size: size,
            child: RepaintBoundary(key: capture, child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> load(WidgetTester tester) async {
    await tester.runAsync(OrionGlassScene.preload);
    expect(LiquidGlassShaders.isLoadedFor(false), isTrue);
  }

  Future<ByteData> pixels(WidgetTester tester) async {
    late ByteData result;
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(capture))
          .toImage(pixelRatio: 1);
      try {
        result = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      } finally {
        image.dispose();
      }
    });
    return result;
  }

  List<int> at(ByteData pixels, int x, int y, {int width = 260}) => [
    for (var c = 0; c < 4; c++) pixels.getUint8((y * width + x) * 4 + c),
  ];

  test('Windows glass optics keep the native radius and frost tuning', () {
    expect(OrionGlassSurface.windowsGlassRefractionIndex, 1.65);
    expect(OrionGlassSurface.windowsGlassRefractionWidth, 52);
    expect(OrionGlassSurface.defaultBlur, 2.25);
    expect(const OrionGlassSurface(child: SizedBox()).blur, 0);
    expect(OrionGlassSurface.windowsGlassRefractionIndex, greaterThan(1));
  });

  testWidgets('inactive scene never loads shaders or adds a capture view', (
    tester,
  ) async {
    expect(LiquidGlassShaders.isLoadedFor(false), isFalse);
    var enabled = false;
    late StateSetter rebuild;
    final probe = GlobalKey<_EditorProbeState>();
    await mount(
      tester,
      StatefulBuilder(
        builder: (_, setState) {
          rebuild = setState;
          return OrionGlassScene(
            enabled: enabled,
            backdrop: const OrionGlassBackdrop(),
            child: OrionGlassSurface(child: _EditorProbe(key: probe)),
          );
        },
      ),
    );
    expect(LiquidGlassShaders.isLoadedFor(false), isFalse);
    expect(find.byType(LiquidGlassView), findsNothing);
    expect(find.byType(LiquidGlassLens), findsNothing);
    final state = probe.currentState!;
    state.text.text = 'ready transition';
    state.focus.requestFocus();
    await tester.pump();
    rebuild(() => enabled = true);
    await tester.pump();
    expect(probe.currentState, same(state));
    await load(tester);
    await tester.pumpAndSettle();
    expect(probe.currentState, same(state));
    expect(state.text.text, 'ready transition');
    expect(state.focus.hasFocus, isTrue);
    rebuild(() => enabled = false);
    await tester.pumpAndSettle();
    expect(probe.currentState, same(state));
    expect(state.focus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Skia shader changes edge sample locations while its center stays unchanged',
    (tester) async {
      await load(tester);
      Widget scene(double index) => OrionGlassScene(
        pixelRatio: 1,
        backdrop: const CustomPaint(painter: _Stripes()),
        child: Center(
          child: SizedBox(
            width: 160,
            height: 90,
            child: LiquidGlassLens(
              useImpellerBackdrop: false,
              honorBackdropAlpha: true,
              style: LiquidGlassStyle(
                shape: const LiquidGlassShape.roundedRectangle(
                  cornerRadius: 20,
                ),
                refractionIndex: index,
                refractionWidth: 24,
                magnification: 1,
                specular: const LiquidGlassLight.specular(intensity: 0),
                glow: const LiquidGlassLight.glow(intensity: 0),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await mount(tester, scene(1));
      final neutral = await pixels(tester);
      await mount(tester, scene(1.22));
      final bent = await pixels(tester);
      var changed = 0;
      for (var y = 55; y < 105; y++) {
        for (var x = 51; x < 75; x++) {
          if ((at(neutral, x, y)[0] - at(bent, x, y)[0]).abs() > 15) changed++;
        }
      }
      expect(
        changed,
        greaterThan(100),
        reason:
            'The shader must move actual stripe samples, not only add a tint.',
      );
      for (var x = 116; x < 144; x++) {
        expect(at(bent, x, 80), at(neutral, x, 80));
      }
      expect(find.byType(LiquidGlassView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'production sheet bends its edge while the clear interior stays pixel exact',
    (tester) async {
      await load(tester);
      const foreground = Center(
        child: SizedBox(
          width: 10,
          height: 10,
          child: ColoredBox(color: Colors.white),
        ),
      );
      Widget scene({required bool lens}) => OrionGlassScene(
        pixelRatio: 1,
        backdrop: const CustomPaint(painter: _Stripes()),
        child: lens
            ? const OrionGlassSurface(
                blur: 0,
                fullSheetRefraction: true,
                child: foreground,
              )
            : foreground,
      );

      await mount(tester, scene(lens: false));
      final baseline = await pixels(tester);
      await mount(tester, scene(lens: true));
      final refracted = await pixels(tester);
      var centerDisplaced = 0;
      for (var y = 28; y < 132; y++) {
        for (var x = 90; x < 170; x++) {
          if (at(refracted, x, y) != at(baseline, x, y)) centerDisplaced++;
        }
      }
      expect(
        centerDisplaced,
        greaterThan(500),
        reason:
            'WindowsGlass bends backdrop samples through the pane, including '
            'its center, while the Flutter foreground stays sharp.',
      );
      var displaced = 0;
      for (var y = 36; y < 124; y++) {
        for (var x = 0; x < 24; x++) {
          if (at(refracted, x, y) != at(baseline, x, y)) displaced++;
        }
      }
      var bodyDisplaced = 0;
      for (var y = 48; y < 112; y++) {
        for (var x = 36; x < 224; x++) {
          if (at(refracted, x, y) != at(baseline, x, y)) bodyDisplaced++;
        }
      }
      expect(
        bodyDisplaced,
        greaterThan(500),
        reason:
            'WindowsGlass applies its shallow lens displacement across the pane, '
            'not only at the 52px bevel.',
      );
      expect(
        displaced,
        greaterThan(0),
        reason: 'The Windows-style full-sheet lens must refract real samples.',
      );
      final lens = tester.widget<LiquidGlassLens>(find.byType(LiquidGlassLens));
      expect(
        lens.style.refractionWidth,
        OrionGlassSurface.windowsGlassRefractionWidth,
      );
      expect(
        lens.style.refractionIndex,
        OrionGlassSurface.windowsGlassRefractionIndex,
      );
      expect(lens.style.specular!.thickness, 2.1);
      expect(lens.style.specular!.intensity, greaterThan(0));
      expect(lens.style.specular!.oppositeIntensity, greaterThan(0));
      expect(lens.style.magnification, 1);
      expect(lens.honorBackdropAlpha, isTrue);
      expect(lens.style.saturation, 1);
      expect(lens.style.glow!.intensity, 0);
      expect(at(refracted, 130, 80), [255, 255, 255, 255]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('glass can disable the heavy edge refraction and rim', (
    tester,
  ) async {
    await load(tester);
    await mount(
      tester,
      const OrionGlassScene(
        pixelRatio: 1,
        backdrop: ColoredBox(color: Color(0xff111b27)),
        child: OrionGlassSurface(
          edgeRefraction: false,
          showRim: false,
          child: SizedBox.expand(),
        ),
      ),
    );
    final lens = tester.widget<LiquidGlassLens>(find.byType(LiquidGlassLens));
    expect(lens.style.refractionIndex, 1);
    expect(lens.style.refractionWidth, 0);
    expect(lens.style.specular, isNull);
    final image = await pixels(tester);
    for (var y = 20; y < 140; y += 4) {
      for (var x = 24; x < 236; x += 4) {
        expect(at(image, x, y), [17, 27, 39, 255]);
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'dark glass has a visible directional caustic without lifting its center',
    (tester) async {
      await load(tester);
      const substrate = Color(0xff111b27);
      await mount(
        tester,
        const OrionGlassScene(
          pixelRatio: 1,
          backdrop: ColoredBox(color: substrate),
          child: OrionGlassSurface(child: SizedBox.expand()),
        ),
      );
      final image = await pixels(tester);
      int edgeLift(int x, int y) => at(image, x, y)[0] - 17;
      var nearPeak = 0;
      var oppositePeak = 0;
      for (var i = 0; i < 4; i++) {
        for (var x = 40; x < 220; x++) {
          nearPeak = nearPeak > edgeLift(x, i) ? nearPeak : edgeLift(x, i);
          oppositePeak = oppositePeak > edgeLift(x, 159 - i)
              ? oppositePeak
              : edgeLift(x, 159 - i);
        }
      }
      expect(
        nearPeak,
        greaterThan(40),
        reason:
            'A real dark backdrop needs a visible polished rim, not a '
            'subpixel highlight that disappears in the assembled app.',
      );
      expect(
        nearPeak - oppositePeak,
        greaterThan(25),
        reason: 'The highlight must be directional rather than a flat outline.',
      );
      for (var y = 20; y < 140; y += 4) {
        for (var x = 24; x < 236; x += 4) {
          expect(at(image, x, y), [17, 27, 39, 255]);
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'glass uses opaque optical coverage and keeps foreground pixels unchanged',
    (tester) async {
      await load(tester);
      await mount(
        tester,
        const OrionGlassScene(
          backdrop: OrionGlassBackdrop(
            tint: Color(0xff1c2431),
            useAuthoredBackground: true,
            backdropOpacity: .5,
          ),
          child: OrionGlassSurface(
            blur: 0,
            fullSheetRefraction: true,
            child: Center(
              child: SizedBox(
                width: 10,
                height: 10,
                child: ColoredBox(color: Colors.white),
              ),
            ),
          ),
        ),
      );
      final image = await pixels(tester);
      expect(at(image, 130, 80), [255, 255, 255, 255]);
      expect(
        at(image, 90, 80)[3],
        inInclusiveRange(120, 136),
        reason:
            'Half-opacity glass must preserve backdrop alpha over the clear scene.',
      );
      expect(OrionGlassSurface.defaultMaterialOpacity, 1);
      final lens = tester.widget<LiquidGlassLens>(find.byType(LiquidGlassLens));
      expect(lens.honorBackdropAlpha, isTrue);
      expect(lens.useImpellerBackdrop, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'activation and readiness preserve editing focus scroll and page state',
    (tester) async {
      var enabled = false;
      late StateSetter rebuild;
      final probe = GlobalKey<_EditorProbeState>();
      await mount(
        tester,
        StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return OrionGlassScene(
              enabled: enabled,
              backdrop: const OrionGlassBackdrop(),
              child: OrionGlassSurface(
                interactive: true,
                child: _EditorProbe(key: probe),
              ),
            );
          },
        ),
      );
      final state = probe.currentState!;
      state.text.text = 'print("preserved")';
      state.focus.requestFocus();
      state.scroll.jumpTo(40);
      await tester.pump();
      rebuild(() => enabled = true);
      await tester.pump();
      await load(tester);
      await tester.pumpAndSettle();
      expect(probe.currentState, same(state));
      expect(state.focus.hasFocus, isTrue);
      expect(state.text.text, 'print("preserved")');
      expect(state.scroll.offset, 40);
      expect(state.page, 3);
      rebuild(() => enabled = false);
      await tester.pumpAndSettle();
      expect(probe.currentState, same(state));
      expect(state.focus.hasFocus, isTrue);
      expect(state.scroll.offset, 40);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'loose and intrinsic dialog surfaces use their actual child size',
    (tester) async {
      await load(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: IntrinsicWidth(
              child: OrionGlassScene(
                backdrop: const OrionGlassBackdrop(),
                child: const OrionGlassSurface(
                  interactive: true,
                  child: SizedBox(
                    width: 240,
                    height: 110,
                    child: Center(child: Text('Notification')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(OrionGlassScene)),
        const Size(240, 110),
      );
      expect(
        tester.getSize(find.byType(LiquidGlassView)),
        const Size(240, 110),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'static captures stay idle, coalesce updates and release image handles',
    (tester) async {
      await load(tester);
      final created = <ui.Image>{};
      final disposed = <ui.Image>{};
      final oldCreate = ui.Image.onCreate;
      final oldDispose = ui.Image.onDispose;
      ui.Image.onCreate = (image) {
        oldCreate?.call(image);
        created.add(image);
      };
      ui.Image.onDispose = (image) {
        oldDispose?.call(image);
        disposed.add(image);
      };
      addTearDown(() {
        ui.Image.onCreate = oldCreate;
        ui.Image.onDispose = oldDispose;
      });
      late StateSetter rebuild;
      var step = 0;
      var foreground = 0;
      await mount(
        tester,
        StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return OrionGlassScene(
              backdrop: OrionGlassBackdrop(tint: Color(0xff18202a + step)),
              child: OrionGlassSurface(
                child: Center(child: Text('$foreground')),
              ),
            );
          },
        ),
      );
      final first = created.length;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(created.length, first);
      rebuild(() => foreground++);
      await tester.pumpAndSettle();
      expect(
        created.length,
        first,
        reason: 'A new equivalent backdrop widget is not a background change.',
      );
      for (var i = 0; i < 12; i++) {
        rebuild(() => step++);
        await tester.pumpAndSettle();
        expect(created.difference(disposed).length, lessThanOrEqualTo(2));
      }
      expect(created.length, greaterThan(first));
      rebuild(() => step++);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(created.difference(disposed), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'material scopes update across zero wrappers without remounting foreground',
    (tester) async {
      await load(tester);
      var enabled = true;
      var opacity = 0.0;
      late StateSetter rebuild;
      final probe = GlobalKey<_EditorProbeState>();
      var materialAncestor = false;
      await mount(
        tester,
        StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return OrionGlassScene(
              backdrop: const OrionGlassBackdrop(),
              child: OrionGlassSurface(
                enabled: enabled,
                materialOpacity: opacity,
                child: OrionGlassSurface(
                  materialOpacity: 0,
                  child: Builder(
                    builder: (context) {
                      materialAncestor = OrionGlassSurface.hasMaterialAncestor(
                        context,
                      );
                      return _EditorProbe(key: probe);
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );
      final state = probe.currentState!;
      state.text.text = 'unchanged';
      state.focus.requestFocus();
      await tester.pump();
      expect(materialAncestor, isFalse);
      rebuild(() => opacity = 1);
      await tester.pump();
      expect(materialAncestor, isTrue);
      final fading = tester.renderObject<RenderAnimatedOpacity>(
        find.byType(AnimatedOpacity).first,
      );
      expect(fading.opacity.value, 0);
      await tester.pump(const Duration(milliseconds: 80));
      expect(fading.opacity.value, inExclusiveRange(0, 1));
      expect(probe.currentState, same(state));
      expect(state.text.text, 'unchanged');
      expect(state.focus.hasFocus, isTrue);
      await tester.pumpAndSettle();
      rebuild(() => enabled = false);
      await tester.pumpAndSettle();
      expect(materialAncestor, isFalse);
      expect(probe.currentState, same(state));
      expect(state.focus.hasFocus, isTrue);
      rebuild(() => enabled = true);
      await tester.pumpAndSettle();
      expect(materialAncestor, isTrue);
      expect(probe.currentState, same(state));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'pointer lights and lens uniforms respond without recapturing the scene',
    (tester) async {
      await load(tester);
      final oldCreate = ui.Image.onCreate;
      var captures = 0;
      ui.Image.onCreate = (image) {
        oldCreate?.call(image);
        captures++;
      };
      addTearDown(() => ui.Image.onCreate = oldCreate);
      await mount(
        tester,
        const OrionGlassScene(
          backdrop: CustomPaint(painter: _Stripes()),
          child: OrionGlassSurface(
            interactive: true,
            child: Center(child: Text('Unwarped label')),
          ),
        ),
      );
      LiquidGlassLens lens() =>
          tester.widget<LiquidGlassLens>(find.byType(LiquidGlassLens));
      final restingAngle = lens().style.specular!.angle;
      final restingRefraction = lens().style.refractionIndex;
      final initialCaptures = captures;
      final textRect = tester.getRect(find.text('Unwarped label'));
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      final surfaceRect = tester.getRect(find.byType(OrionGlassSurface));
      await mouse.moveTo(surfaceRect.topLeft + const Offset(30, 30));
      await tester.pumpAndSettle();
      final leftAngle = lens().style.specular!.angle;
      expect(leftAngle, lessThan(restingAngle));
      expect(lens().style.refractionIndex, greaterThan(restingRefraction));
      await mouse.moveTo(surfaceRect.bottomRight - const Offset(30, 30));
      await tester.pumpAndSettle();
      expect(lens().style.specular!.angle, greaterThan(leftAngle + 20));
      expect(tester.getRect(find.text('Unwarped label')), textRect);
      expect(captures, initialCaptures);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(lens().style.specular!.angle, restingAngle);
      expect(captures, initialCaptures);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('reduced motion keeps pointer optics and flex stationary', (
    tester,
  ) async {
    await load(tester);
    await mount(
      tester,
      const OrionGlassScene(
        reducedMotion: true,
        backdrop: OrionGlassBackdrop(),
        child: OrionGlassSurface(
          interactive: true,
          child: Center(child: Text('Still')),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getTopLeft(find.byType(OrionGlassSurface)) + const Offset(10, 10),
    );
    await tester.pump();
    final lens = tester.widget<LiquidGlassLens>(find.byType(LiquidGlassLens));
    expect(lens.style.specular!.angle, -135);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).duration,
      Duration.zero,
    );
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'authored glass preserves gradient geometry and supports solid backgrounds',
    () {
      const transform = GradientRotation(.6);
      const source = LinearGradient(
        begin: Alignment(-.7, .2),
        end: Alignment(.8, -.1),
        colors: [Color(0xffa63c70), Color(0x803fa755), Color(0xff315dc7)],
        stops: [0, .23, 1],
        tileMode: TileMode.mirror,
        transform: transform,
      );
      const base = Color(0xff18202a);
      final glass = OrionGlassBackdrop.gradientFor(
        base,
        authoredGradient: source,
        useAuthoredBackground: true,
      );
      expect(glass.begin, source.begin);
      expect(glass.end, source.end);
      expect(glass.stops, source.stops);
      expect(glass.tileMode, source.tileMode);
      expect(glass.transform, same(transform));
      for (var i = 0; i < source.colors.length; i++) {
        expect(
          glass.colors[i].toARGB32() & 0xffffff,
          source.colors[i].toARGB32() & 0xffffff,
        );
        expect(glass.colors[i].a, 1);
      }
      final solid = OrionGlassBackdrop.gradientFor(
        base,
        useAuthoredBackground: true,
      );
      expect(solid.colors[0], solid.colors[1]);
      expect(solid.colors[0].toARGB32() & 0xffffff, base.toARGB32() & 0xffffff);
      expect(solid.colors[0].a, 1);
      final light = OrionGlassBackdrop.gradientFor(
        Colors.white,
        useAuthoredBackground: true,
      );
      expect(light.colors[0].a, 1);
      expect(OrionGlassBackdrop.gradientFor(base).colors, isNot(solid.colors));
      expect(OrionGlassBackdrop.lightsFor(const Color(0xff102030)), isEmpty);
      expect(OrionGlassBackdrop.lightsFor(Colors.white), isEmpty);
    },
  );

  testWidgets(
    'authored gradient colors and angle refresh the static refractive capture',
    (tester) async {
      await load(tester);
      final oldCreate = ui.Image.onCreate;
      var images = 0;
      ui.Image.onCreate = (image) {
        oldCreate?.call(image);
        images++;
      };
      addTearDown(() => ui.Image.onCreate = oldCreate);
      late StateSetter rebuild;
      var horizontal = false;
      var green = false;
      var foreground = 0;
      await mount(
        tester,
        StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return OrionGlassScene(
              pixelRatio: 1,
              backdrop: OrionGlassBackdrop(
                tint: const Color(0xff18202a),
                useAuthoredBackground: true,
                authoredGradient: LinearGradient(
                  begin: horizontal
                      ? Alignment.centerLeft
                      : Alignment.topCenter,
                  end: horizontal
                      ? Alignment.centerRight
                      : Alignment.bottomCenter,
                  colors: [
                    green ? const Color(0xff29ba70) : const Color(0xffd53a62),
                    const Color(0xff4264d8),
                  ],
                  stops: const [0, 1],
                ),
              ),
              child: OrionGlassSurface(
                blur: 0,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Text('$foreground'),
                ),
              ),
            );
          },
        ),
      );
      final first = await pixels(tester);
      final afterFirst = images;
      rebuild(() => foreground++);
      await tester.pumpAndSettle();
      expect(
        images,
        afterFirst,
        reason: 'A semantically equivalent authored gradient must remain idle.',
      );
      rebuild(() => green = true);
      await tester.pumpAndSettle();
      expect(images, greaterThan(afterFirst));
      final changed = await pixels(tester);
      expect(at(changed, 50, 40), isNot(at(first, 50, 40)));
      final afterColor = images;
      rebuild(() => horizontal = true);
      await tester.pumpAndSettle();
      expect(
        images,
        greaterThan(afterColor),
        reason: 'Direction/angle alone must invalidate capture.',
      );
      final rotated = await pixels(tester);
      expect(at(rotated, 60, 120), isNot(at(changed, 60, 120)));
      final idle = images;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(images, idle);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
