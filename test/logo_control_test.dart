import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/widgets/orion_overlay.dart';
import 'package:orion/widgets/logo_control.dart';
import 'package:orion/widgets/logo_crop_dialog.dart';
import 'package:orion/widgets/orion_logo.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

class _OversizedImage extends files.XFile {
  _OversizedImage() : super('/not-read.png');
  bool read = false;
  @override
  Future<int> length() async => maximumLogoInputBytes + 1;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    read = true;
    throw StateError('Oversized images must never be read.');
  }
}

Future<ui.Image> _solid(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

Future<Uint8List> _png(ui.Image image) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<void> _wait(WidgetTester tester, bool Function() done) async {
  final watch = Stopwatch()..start();
  while (!done() && watch.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), true);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ui.Image source;
  late Uint8List sourceBytes;
  setUpAll(() async {
    source = await _solid(40, 40, const Color(0xffff0000));
    sourceBytes = await _png(source);
  });
  tearDownAll(() => source.dispose());

  testWidgets(
    'preview and crop checkers follow the theme and repaint on change',
    (tester) async {
      Future<List<int>> swatches(CustomPainter painter) async {
        final result = await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), const Size(48, 12));
          final picture = recorder.endRecording();
          final image = await picture.toImage(48, 12);
          try {
            final pixels = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            return [
              for (final x in [2, 14])
                for (var channel = 0; channel < 4; channel++)
                  pixels.getUint8((2 * 48 + x) * 4 + channel),
            ];
          } finally {
            image.dispose();
            picture.dispose();
          }
        });
        return result!;
      }

      Future<List<CustomPainter>> painters(Brightness brightness) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: Column(
                children: [
                  const LogoCheckerboard(
                    child: SizedBox(width: 24, height: 12),
                  ),
                  Expanded(child: LogoCropDialog(image: source)),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return [
          tester
              .widget<CustomPaint>(
                find.descendant(
                  of: find.byType(LogoCheckerboard),
                  matching: find.byType(CustomPaint),
                ),
              )
              .painter!,
          tester
              .widget<CustomPaint>(
                find.descendant(
                  of: find.byKey(const ValueKey('logo-crop-viewport')),
                  matching: find.byType(CustomPaint),
                ),
              )
              .painter!,
        ];
      }

      final dark = await painters(Brightness.dark);
      final light = await painters(Brightness.light);
      for (var index = 0; index < dark.length; index++) {
        final darkPixels = await swatches(dark[index]);
        final lightPixels = await swatches(light[index]);
        expect(darkPixels[3], 255);
        expect(darkPixels[7], 255);
        expect(lightPixels[3], 255);
        expect(lightPixels[7], 255);
        expect(
          darkPixels.take(3).toList(),
          isNot(darkPixels.skip(4).take(3).toList()),
        );
        expect(
          lightPixels.take(3).toList(),
          isNot(lightPixels.skip(4).take(3).toList()),
        );
        expect(darkPixels[0], lessThan(lightPixels[0]));
        expect(darkPixels, isNot(lightPixels));
        expect(light[index].shouldRepaint(dark[index]), true);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('logo crop follows live themes and keeps its crop transform', (
    tester,
  ) async {
    final c = OrionController(persistChanges: false)..setReducedMotion(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LogoControl(
            controller: c,
            onChanged: (_) {},
            pickImage: () async =>
                files.XFile.fromData(sourceBytes, name: 'logo.png'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('logo-choose-image')));
    await _wait(
      tester,
      () => find.byType(LogoCropDialog).evaluate().isNotEmpty,
    );
    final zoom = find.byType(Slider);
    tester.widget<Slider>(zoom).onChanged!(1.6);
    await tester.pumpAndSettle();
    final oldPainter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const ValueKey('logo-crop-viewport')),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    c.setOrionTheme(
      OrionThemePreferences.builtInPresets
          .singleWhere((p) => p.id == 'original-orion')
          .preferences,
    );
    await tester.pumpAndSettle();
    final colors = OrionColors.of(
      tester.element(find.byType(OrionOverlaySurface)),
    );
    expect(colors.accent, OrionThemePreferences.originalAccent);
    final surface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('orion-overlay-decoration')),
    );
    expect(
      (surface.decoration! as BoxDecoration).gradient,
      colors.backgroundGradient,
    );
    expect(tester.widget<Slider>(zoom).value, 1.6);
    final nextPainter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const ValueKey('logo-crop-viewport')),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    expect(nextPainter.shouldRepaint(oldPainter), true);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test(
    'initial fitting preserves image aspect and both fit/fill reset the drag offset',
    () {
      final fit = LogoCropTransform(imageSize: const Size(40, 40));
      expect(fit.destination, const Rect.fromLTWH(510.5, 0, 387, 387));
      expect(
        fit.moved(const Offset(100, 30)).withZoom(2).destination.center,
        const Offset(804, 223.5),
      );
      expect(
        fit.moved(const Offset(100, 30)).fit().destination,
        fit.destination,
      );
      final fill = fit.moved(const Offset(100, 30)).fill();
      expect(fill.destination.left, closeTo(0, .001));
      expect(fill.destination.width, closeTo(1408, .001));
      expect(fill.destination.center, logoOutputSize.center(Offset.zero));
      final exact = LogoCropTransform(imageSize: logoOutputSize);
      expect(exact.destination, Offset.zero & logoOutputSize);
    },
  );

  test(
    'crop output is exactly 1408x387 and preserves transparent letterbox pixels without checkerboard',
    () async {
      final png = await renderLogoCrop(
        source,
        const LogoCropTransform(imageSize: Size(40, 40)),
      );
      final decoded = await decodeLogoImage(png);
      try {
        expect(
          Size(decoded.width.toDouble(), decoded.height.toDouble()),
          logoOutputSize,
        );
        final rgba = (await decoded.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        int pixel(int x, int y, int channel) =>
            rgba.getUint8((y * decoded.width + x) * 4 + channel);
        expect(pixel(0, 0, 3), 0);
        expect(pixel(1407, 386, 3), 0);
        expect(
          [
            for (var channel = 0; channel < 4; channel++)
              pixel(704, 193, channel),
          ],
          [255, 0, 0, 255],
        );
      } finally {
        decoded.dispose();
      }
    },
  );

  test(
    'pan and zoom are rendered from source pixels and clipped at the output frame',
    () async {
      const transform = LogoCropTransform(
        imageSize: Size(40, 40),
        zoom: 2,
        offset: Offset(600, 0),
      );
      final decoded = await decodeLogoImage(
        await renderLogoCrop(source, transform),
      );
      try {
        final rgba = (await decoded.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        expect(rgba.getUint8((193 * 1408 + 500) * 4 + 3), 0);
        expect(rgba.getUint8((193 * 1408 + 1407) * 4 + 3), 255);
      } finally {
        decoded.dispose();
      }
    },
  );

  test('decode rejects unsupported or corrupt images safely', () async {
    await expectLater(
      decodeLogoImage(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    await expectLater(
      decodeLogoImage(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0])),
      throwsA(isA<Object>()),
    );
  });

  Future<void> mount(
    WidgetTester tester, {
    Uint8List? image,
    required ValueChanged<Uint8List?> onChanged,
    Future<files.XFile?> Function()? pickImage,
    Size size = const Size(822, 523),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: orionTheme(Brightness.dark, const Color(0xff88b5ff)),
        builder: (_, child) => UiScaleViewport(scale: scale, child: child!),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: LogoControl(
              image: image,
              onChanged: onChanged,
              pickImage:
                  pickImage ??
                  () async =>
                      files.XFile.fromData(sourceBytes, name: 'square.png'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('logo-choose-image')));
    await _wait(
      tester,
      () => find.byType(LogoCropDialog).evaluate().isNotEmpty,
    );
  }

  testWidgets(
    'picker opens fitted crop, pan/zoom reset with Fit, and Apply emits transparent PNG',
    (tester) async {
      Uint8List? applied;
      await mount(tester, onChanged: (value) => applied = value);
      await choose(tester);
      expect(find.text('100%'), findsOneWidget);
      final viewport = find.byKey(const ValueKey('logo-crop-viewport'));
      expect(tester.getSize(viewport).aspectRatio, closeTo(1408 / 387, .001));
      await tester.drag(viewport, const Offset(30, 0));
      await tester.pumpAndSettle();
      tester
          .widget<Slider>(find.byKey(const ValueKey('logo-crop-zoom')))
          .onChanged!(math.log(2));
      await tester.pumpAndSettle();
      expect(find.text('200%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('logo-crop-fit')));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('logo-crop-apply')));
      await _wait(tester, () => applied != null);
      final decoded = await tester.runAsync(() => decodeLogoImage(applied!));
      try {
        expect(decoded!.width, 1408);
        expect(decoded.height, 387);
        final rgba = await tester.runAsync(
          () => decoded.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        expect(rgba!.getUint8(3), 0);
        expect(rgba.getUint8((193 * 1408 + 704) * 4 + 3), 255);
      } finally {
        decoded?.dispose();
      }
      expect(find.byType(LogoCropDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cancel keeps the current logo and Restore emits null', (
    tester,
  ) async {
    final changes = <Uint8List?>[];
    await mount(tester, image: sourceBytes, onChanged: changes.add);
    await choose(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('logo-restore')));
    await tester.pumpAndSettle();
    expect(changes, [null]);
  });

  testWidgets(
    'oversized files are rejected before reading and decode errors leave the logo unchanged',
    (tester) async {
      final file = _OversizedImage();
      final changes = <Uint8List?>[];
      await mount(tester, onChanged: changes.add, pickImage: () async => file);
      await tester.tap(find.byKey(const ValueKey('logo-choose-image')));
      await _wait(
        tester,
        () => find
            .text('Choose an image smaller than 20 MB.')
            .evaluate()
            .isNotEmpty,
      );
      expect(file.read, false);
      expect(changes, isEmpty);
      await mount(
        tester,
        onChanged: changes.add,
        pickImage: () async => files.XFile.fromData(
          Uint8List.fromList([0, 1, 2]),
          name: 'bad.png',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('logo-choose-image')));
      await _wait(
        tester,
        () => find
            .text('Choose a PNG, JPEG or WebP image.')
            .evaluate()
            .isNotEmpty,
      );
      expect(find.byType(LogoCropDialog), findsNothing);
      expect(changes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(680, 420), const Size(822, 523)]) {
    testWidgets(
      'crop controls fit ${size.width}x${size.height} at 125 percent and keyboard can move the logo',
      (tester) async {
        await mount(tester, onChanged: (_) {}, size: size, scale: 1.25);
        await choose(tester);
        expect(tester.takeException(), isNull);
        final before = tester.getCenter(
          find.byKey(const ValueKey('logo-crop-viewport')),
        );
        await tester.tapAt(before);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('logo-crop-fill')),
        );
        await tester.tap(find.byKey(const ValueKey('logo-crop-fill')));
        await tester.pumpAndSettle();
        expect(find.text('364%'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'custom and original wordmarks keep identical header bounds and custom colors in light mode',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: orionTheme(Brightness.light, Colors.blue),
          home: Scaffold(
            body: Column(
              children: [
                const OrionWordmark(key: ValueKey('default'), height: 24),
                OrionWordmark(
                  key: const ValueKey('custom'),
                  height: 24,
                  customImage: sourceBytes,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('custom'))),
        tester.getSize(find.byKey(const ValueKey('default'))),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('custom'))),
        const Size(1408 / 387 * 24, 24),
      );
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const ValueKey('custom')),
          matching: find.byType(Image),
        ),
      );
      expect(image.color, isNull);
      expect((image.image as MemoryImage).bytes, orderedEquals(sourceBytes));
    },
  );

  testWidgets(
    'corrupt custom wordmark falls back to the original within the same slot',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrionWordmark(
              height: 24,
              customImage: Uint8List.fromList([0, 1, 2]),
            ),
          ),
        ),
      );
      await _wait(
        tester,
        () => find
            .image(const AssetImage('assets/branding/orion-wordmark.png'))
            .evaluate()
            .isNotEmpty,
      );
      expect(
        tester.getSize(find.byType(OrionWordmark).first),
        const Size(1408 / 387 * 24, 24),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
