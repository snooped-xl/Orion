import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/companion_window.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/screens/theme_control_screen.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';

const _studioKey = ValueKey('orion-theme-studio');
const _captureKey = ValueKey('theme-control-capture');

class _StudioHost implements CompanionWindowHost {
  final opened = <CompanionWindowKind>[];

  @override
  Future<void> open(CompanionWindowKind kind, {String? documentId}) async =>
      opened.add(kind);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Pixels {
  const _Pixels(this.bytes, this.width);
  final ByteData bytes;
  final int width;

  int at(Offset point) =>
      bytes.getUint32((point.dy.floor() * width + point.dx.floor()) * 4);
}

Future<_Pixels> _capture(WidgetTester tester, {String? name}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (const bool.fromEnvironment('THEME_CONTROL_STATE_SCREENSHOTS') &&
        name != null) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '../../work/theme-control-$name.png',
      ).writeAsBytes(png!.buffer.asUint8List());
    }
    final pixels = _Pixels(bytes!, image.width);
    image.dispose();
    return pixels;
  }))!;
}

Future<OrionController> _mount(
  WidgetTester tester,
  OrionThemePreferences preferences, {
  Size size = const Size(700, 450),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = OrionController(persistChanges: false);
  controller.setOrionTheme(preferences);
  await tester.pumpWidget(
    MaterialApp(
      theme: orionTheme(
        Brightness.dark,
        preferences.accent,
        preferences: preferences,
      ),
      home: RepaintBoundary(
        key: _captureKey,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: ThemeControlScreen(controller: controller),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  return controller;
}

void _expectFullCardState(_Pixels idle, _Pixels active, Rect card) {
  // This strip was outside the old inset ListTile's rectangular state layer.
  for (final x in [3.0, 6.0, 10.0]) {
    final point = Offset(card.left + x, card.center.dy);
    expect(active.at(point), isNot(idle.at(point)), reason: 'Card edge at $x');
  }
  // The rounded corner must remain outside hover/focus/pressed paint.
  final corner = card.topLeft + const Offset(2, 2);
  expect(active.at(corner), idle.at(corner));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'RobotoFlex',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final preset in OrionThemePreferences.builtInPresets.take(3)) {
    testWidgets(
      '${preset.name} Studio hover follows the full rounded surface',
      (tester) async {
        await _mount(tester, preset.preferences);
        final tile = find.byKey(_studioKey);
        final card = tester.getRect(tile);
        final materialFinder = find
            .ancestor(of: tile, matching: find.byType(Material))
            .first;
        final material = tester.widget<Material>(materialFinder);
        final colors = OrionColors.of(tester.element(tile));
        expect(tester.getRect(materialFinder), card);
        expect(material.color, colors.chrome(colors.panel, role: 'panel'));
        expect(material.clipBehavior, Clip.antiAlias);

        final idle = await _capture(tester);
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await pointer.addPointer(location: const Offset(1, 1));
        await pointer.moveTo(card.center);
        await tester.pumpAndSettle();
        _expectFullCardState(
          idle,
          await _capture(tester, name: '${preset.id}-hover'),
          card,
        );
        await pointer.removePointer();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Studio keyboard focus and press share the rounded card bounds', (
    tester,
  ) async {
    final controller = await _mount(tester, OrionThemePreferences.defaults);
    final host = _StudioHost();
    controller.companionWindows = host;
    final card = tester.getRect(find.byKey(_studioKey));
    final idle = await _capture(tester);
    final previousStrategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() {
      FocusManager.instance.highlightStrategy = previousStrategy;
    });
    final focus = Focus.of(tester.element(find.text('Theme Studio')));
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasPrimaryFocus, true);
    _expectFullCardState(idle, await _capture(tester, name: 'focus'), card);

    focus.unfocus();
    await tester.pumpAndSettle();
    final press = await tester.startGesture(card.center);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    _expectFullCardState(idle, await _capture(tester, name: 'pressed'), card);
    await press.cancel();
    await tester.pumpAndSettle();
    expect(host.opened, isEmpty);

    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(host.opened, [CompanionWindowKind.orionThemeStudio]);
    expect(controller.orionTheme, OrionThemePreferences.defaults);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Studio section keeps rounded states in a narrow theme page', (
    tester,
  ) async {
    await _mount(
      tester,
      OrionThemePreferences.defaults,
      size: const Size(480, 400),
    );
    final card = tester.getRect(find.byKey(_studioKey));
    expect(card.width, 456);
    expect(card.height, greaterThanOrEqualTo(72));
    final idle = await _capture(tester);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: const Offset(1, 1));
    await pointer.moveTo(card.center);
    await tester.pumpAndSettle();
    _expectFullCardState(idle, await _capture(tester), card);
    await pointer.removePointer();
    expect(tester.takeException(), isNull);
  });
}
