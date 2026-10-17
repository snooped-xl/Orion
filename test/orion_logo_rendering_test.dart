import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/widgets/orion_logo.dart';

class _OldWordmark extends StatelessWidget {
  const _OldWordmark();
  @override
  Widget build(BuildContext context) {
    const height = 28.0;
    const scale = height / 387;
    return SizedBox(
      width: 1408 * scale,
      height: height,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: -152 * scale,
            top: -275 * scale,
            width: 1692 * scale,
            height: 929 * scale,
            child: Image.asset(
              'assets/branding/orion-wordmark.png',
              filterQuality: FilterQuality.high,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scale in [1.0, 1.25]) {
    testWidgets('supplied wordmark keeps smooth coverage at GUI $scale', (
      tester,
    ) async {
      final key = GlobalKey();
      Future<Uint8List> render(Widget child) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 1408 / 387 * 28 * scale,
                  height: 28 * scale,
                  child: FittedBox(child: child),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/branding/orion-wordmark.png'),
            tester.element(find.byKey(key)),
          ),
        );
        await tester.pumpAndSettle();
        late Uint8List data;
        await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(find.byKey(key))
              .toImage();
          try {
            data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
          } finally {
            image.dispose();
          }
        });
        return data;
      }

      final old = await render(const _OldWordmark());
      final current = await render(const OrionWordmark(height: 28));
      int edges(Uint8List bytes) {
        var count = 0;
        for (var i = 3; i < bytes.length; i += 4) {
          if (bytes[i] > 0 && bytes[i] < 255) count++;
        }
        return count;
      }

      expect(edges(current), greaterThan(edges(old) * 1.15));
      double coverage(Uint8List bytes) {
        var total = 0;
        for (var i = 3; i < bytes.length; i += 4) {
          total += bytes[i];
        }
        return total / 255;
      }

      expect(coverage(current), closeTo(coverage(old), coverage(old) * .06));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
