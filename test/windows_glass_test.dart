import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:orion/widgets/orion_glass.dart';

class _Stripes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 8, size.height),
        Paint()..color = (x ~/ 8).isEven ? Colors.red : Colors.blue,
      );
    }
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}

void main() {
  testWidgets(
    'Windows optimized capture shader refracts edges and preserves clear center',
    (tester) async {
      // Widget tests default to Android. This variant must preload and paint
      // the desktop asset selected for the Windows capture pipeline.
      await tester.runAsync(OrionGlassScene.preload);
      expect(LiquidGlassShaders.isLoadedFor(false), isTrue);
      final capture = GlobalKey();
      Future<ByteData> render(double refraction) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 260,
                height: 160,
                child: RepaintBoundary(
                  key: capture,
                  child: OrionGlassScene(
                    pixelRatio: 1,
                    backdrop: CustomPaint(painter: _Stripes()),
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
                            refractionIndex: refraction,
                            refractionWidth: 24,
                            magnification: 1,
                            specular: const LiquidGlassLight.specular(
                              intensity: 0,
                            ),
                            glow: const LiquidGlassLight.glow(intensity: 0),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return (await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(find.byKey(capture))
              .toImage(pixelRatio: 1);
          try {
            return (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
          } finally {
            image.dispose();
          }
        }))!;
      }

      final neutral = await render(1);
      final refracted = await render(1.22);
      var changedEdgePixels = 0;
      for (var y = 55; y < 105; y++) {
        for (var x = 51; x < 75; x++) {
          final index = (y * 260 + x) * 4;
          if ((neutral.getUint8(index) - refracted.getUint8(index)).abs() >
              15) {
            changedEdgePixels++;
          }
        }
      }
      expect(changedEdgePixels, greaterThan(100));
      for (var x = 116; x < 144; x++) {
        for (var channel = 0; channel < 4; channel++) {
          final index = (80 * 260 + x) * 4 + channel;
          expect(refracted.getUint8(index), neutral.getUint8(index));
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
