import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/native_desktop_glass.dart';
import 'package:orion/widgets/orion_glass.dart';

final glassy = OrionThemePreferences.builtInPresets
    .singleWhere((p) => p.id == 'liquid-glass')
    .preferences;
const shapes = <String, BorderRadius>{
  'rounded twelve': BorderRadius.all(Radius.circular(12)),
  'asymmetric ten/two': BorderRadius.only(
    topLeft: Radius.circular(10),
    bottomLeft: Radius.circular(10),
    topRight: Radius.circular(2),
    bottomRight: Radius.circular(2),
  ),
};
Widget fixture(
  Key capture,
  BorderRadius corners,
  bool sheet, [
  WidgetStatesController? states,
]) {
  final button = SizedBox(
    width: 120,
    height: 48,
    child: FilledButton(
      statesController: states,
      onPressed: () {},
      style: FilledButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: corners),
        side: const BorderSide(color: Colors.white),
        overlayColor: Colors.transparent,
      ),
      child: const SizedBox.shrink(),
    ),
  );
  return MaterialApp(
    theme: orionTheme(
      Brightness.dark,
      Colors.blue,
      preferences: glassy,
      reducedMotion: true,
    ),
    home: Center(
      child: RepaintBoundary(
        key: capture,
        child: SizedBox(
          width: 160,
          height: 88,
          child: NativeDesktopGlassScope(
            active: sheet,
            opacity: 1,
            child: OrionGlassScene(
              reducedMotion: true,
              backdrop: const ColoredBox(color: Colors.black),
              child: sheet
                  ? OrionGlassSurface(
                      tint: Colors.transparent,
                      child: Center(child: button),
                    )
                  : Center(child: button),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<List<int>> pixel(WidgetTester tester, Key key, int x, int y) async {
  late List<int> result;
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(key))
        .toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    result = List.generate(4, (c) => bytes.getUint8((y * 160 + x) * 4 + c));
    image.dispose();
  });
  return result;
}

void main() {
  for (final entry in shapes.entries) {
    testWidgets('Glassy ${entry.key} fill reaches explicit outline corners', (
      tester,
    ) async {
      final key = GlobalKey();
      final states = WidgetStatesController();
      addTearDown(states.dispose);
      await tester.pumpWidget(fixture(key, entry.value, true, states));
      await tester.pumpAndSettle();
      // All samples lie inside the explicit outline but outside radius20.
      final samples = entry.key == 'rounded twelve'
          ? const [Offset(5, 5), Offset(114, 5), Offset(5, 42), Offset(114, 42)]
          : const [
              Offset(4, 4),
              Offset(115, 4),
              Offset(4, 43),
              Offset(115, 43),
            ];
      for (final state in [
        null,
        WidgetState.hovered,
        WidgetState.focused,
        WidgetState.pressed,
      ]) {
        states.value = state == null ? {} : {state};
        await tester.pumpAndSettle();
        expect((await pixel(tester, key, 80, 44))[2], greaterThan(15));
        for (final point in samples) {
          expect(
            (await pixel(
              tester,
              key,
              20 + point.dx.toInt(),
              20 + point.dy.toInt(),
            ))[2],
            greaterThan(15),
            reason: '${entry.key} $state corner $point requires accent fill',
          );
        }
        expect(
          (await pixel(tester, key, 80, 20)).take(3),
          everyElement(greaterThan(170)),
          reason: 'The white outline must remain independently visible',
        );
        final stroke = await pixel(tester, key, 80, 20);
        expect(
          (stroke[0] - stroke[2]).abs(),
          lessThan(4),
          reason: 'The accent fill must not tint the white outline',
        );
        expect(
          (await pixel(tester, key, 20, 20)).take(3),
          everyElement(lessThan(8)),
        );
      }
      expect(tester.takeException(), isNull);
    });
    testWidgets('Glassy fallback lens follows Material ${entry.key}', (
      tester,
    ) async {
      await tester.runAsync(OrionGlassScene.preload);
      await tester.pumpWidget(fixture(GlobalKey(), entry.value, false));
      await tester.pumpAndSettle();
      final lens = tester.widget<OrionGlassSurface>(
        find.byType(OrionGlassSurface),
      );
      expect(lens.borderRadius, entry.value);
      expect(lens.shape, RoundedRectangleBorder(borderRadius: entry.value));
      expect(tester.takeException(), isNull);
    });
  }
}
