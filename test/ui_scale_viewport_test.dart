import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

void main() {
  testWidgets(
    'global scale transforms paint and hit boxes with logical media',
    (tester) async {
      const actual = Size(720, 480);
      tester.view.physicalSize = actual * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const targetKey = ValueKey('scaled-hit-target');
      var hits = 0;
      MediaQueryData? observed;
      BoxConstraints? layout;
      for (final scale in [.8, 1.0, 1.25]) {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: actual,
              devicePixelRatio: 2,
              padding: EdgeInsets.fromLTRB(16, 24, 32, 48),
              viewPadding: EdgeInsets.fromLTRB(20, 28, 36, 52),
              viewInsets: EdgeInsets.only(bottom: 120),
              systemGestureInsets: EdgeInsets.all(8),
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: UiScaleViewport(
                scale: scale,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    observed = MediaQuery.of(context);
                    layout = constraints;
                    return Stack(
                      children: [
                        Positioned(
                          left: 80,
                          top: 60,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => hits++,
                            child: const SizedBox(
                              key: targetKey,
                              width: 120,
                              height: 40,
                              child: ColoredBox(color: Colors.blue),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        expect(layout!.biggest, actual / scale);
        expect(observed!.size, actual / scale);
        expect(observed!.devicePixelRatio, 2);
        expect(
          observed!.padding,
          const EdgeInsets.fromLTRB(16, 24, 32, 48) / scale,
        );
        expect(
          observed!.viewPadding,
          const EdgeInsets.fromLTRB(20, 28, 36, 52) / scale,
        );
        expect(observed!.viewInsets.bottom, 120 / scale);
        expect(observed!.systemGestureInsets.left, 8 / scale);

        final box = tester.renderObject<RenderBox>(find.byKey(targetKey));
        expect(box.size, const Size(120, 40));
        final painted = Rect.fromPoints(
          box.localToGlobal(Offset.zero),
          box.localToGlobal(box.size.bottomRight(Offset.zero)),
        );
        expect(painted.left, closeTo(80 * scale, .001));
        expect(painted.top, closeTo(60 * scale, .001));
        expect(painted.width, closeTo(120 * scale, .001));
        expect(painted.height, closeTo(40 * scale, .001));
        final before = hits;
        await tester.tapAt(painted.center);
        expect(hits, before + 1);
        await tester.tapAt(Offset(painted.right + 8, painted.center.dy));
        expect(hits, before + 1);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
