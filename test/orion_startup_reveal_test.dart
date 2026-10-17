import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/orion_logo.dart';
import 'package:orion/widgets/orion_startup_reveal.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

void main() {
  testWidgets('logo leaves before the themed cover finishes revealing Orion', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false);
    addTearDown(controller.dispose);
    var completions = 0;
    await _mount(tester, controller, () => completions++);

    Offset translation(String key) {
      final matrix = tester
          .widget<Transform>(find.byKey(ValueKey(key)))
          .transform;
      return Offset(matrix.storage[12], matrix.storage[13]);
    }

    expect(translation('orion-startup-cover'), Offset.zero);
    await tester.pump(const Duration(milliseconds: 260));
    expect(translation('orion-startup-logo').dy.abs(), lessThan(1));
    expect(translation('orion-startup-cover'), Offset.zero);
    await tester.pump(const Duration(milliseconds: 200));
    expect(translation('orion-startup-logo').dy, lessThan(-20));
    expect(translation('orion-startup-cover'), Offset.zero);
    await tester.pump(const Duration(milliseconds: 300));
    expect(translation('orion-startup-logo').dy, lessThan(-300));
    expect(translation('orion-startup-cover').dy, lessThan(-100));
    expect(completions, 0);
    await tester.pump(const Duration(milliseconds: 189));
    expect(completions, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(completions, 1);
    expect(translation('orion-startup-cover').dy, lessThan(-523));
    await tester.pump(const Duration(seconds: 5));
    expect(completions, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing before completion never invokes the callback', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false);
    addTearDown(controller.dispose);
    var completions = 0;
    await _mount(tester, controller, () => completions++);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(completions, 0);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  for (final system in [false, true]) {
    testWidgets(
      '${system ? 'system' : 'preference'} reduced motion reveals immediately',
      (tester) async {
        final controller = OrionController(persistChanges: false);
        addTearDown(controller.dispose);
        if (!system) controller.setReducedMotion(true);
        var completions = 0;
        await _mount(
          tester,
          controller,
          () => completions++,
          systemReducedMotion: system,
        );
        expect(completions, 1);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pump(const Duration(seconds: 2));
        expect(completions, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('enabling reduced motion during startup ends the cover safely', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false);
    addTearDown(controller.dispose);
    var completions = 0;
    await _mount(tester, controller, () => completions++);
    await tester.pump(const Duration(milliseconds: 350));
    controller.setReducedMotion(true);
    await tester.pump();
    expect(completions, 1);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(completions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the cover blocks interaction until the host removes it', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false);
    addTearDown(controller.dispose);
    var presses = 0;
    var showCover = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: orionTheme(Brightness.dark, controller.accentColor),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: FilledButton(
                    onPressed: () => presses++,
                    child: const Text('Editor action'),
                  ),
                ),
                if (showCover)
                  OrionStartupReveal(
                    controller: controller,
                    onComplete: () => setState(() => showCover = false),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.text('Editor action')));
    expect(presses, 0);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tapAt(tester.getCenter(find.text('Editor action')));
    expect(presses, 0);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Editor action'));
    expect(presses, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final theme in [
    ...OrionThemePreferences.builtInPresets.take(4).map((p) => p.preferences),
    OrionThemePreferences(
      presetId: 'custom-linen',
      themeMode: ThemeMode.light,
      accent: const Color(0xFF865D31),
      gradientEnabled: true,
      gradientColors: const [Color(0xFFF8F1E6), Color(0xFFDDD2BC)],
      overrides: const {'background': Color(0xFFF7F0E1)},
    ),
  ]) {
    testWidgets(
      '${theme.presetId} follows the selected theme in compact mode',
      (tester) async {
        final controller = OrionController(persistChanges: false)
          ..setOrionTheme(theme);
        addTearDown(controller.dispose);
        await _mount(
          tester,
          controller,
          () {},
          size: const Size(680, 420),
          scale: 1.25,
        );
        final context = tester.element(find.byType(OrionStartupReveal));
        final colors = OrionColors.of(context);
        final cover = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byKey(const ValueKey('orion-startup-cover')),
            matching: find.byType(DecoratedBox),
          ),
        );
        final decoration = cover.decoration as BoxDecoration;
        expect(decoration.color, colors.background);
        expect(decoration.gradient, colors.backgroundGradient);
        expect(find.byType(OrionWordmark), findsOneWidget);
        expect(find.byType(Text), findsNothing);
        await tester.pump(const Duration(milliseconds: 300));
        final logo = tester.getRect(find.byType(OrionWordmark));
        expect(logo.width, lessThan(680 - 60));
        expect(logo.center.dx, closeTo(340, .1));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('a custom logo uses the existing cropped branding image', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false)
      ..setCustomLogo(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j2ioAAAAASUVORK5CYII=',
        ),
      );
    addTearDown(controller.dispose);
    await _mount(tester, controller, () {});
    final wordmark = tester.widget<OrionWordmark>(find.byType(OrionWordmark));
    expect(wordmark.customImage, controller.customLogoBytes);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _mount(
  WidgetTester tester,
  OrionController controller,
  VoidCallback onComplete, {
  bool systemReducedMotion = false,
  Size size = const Size(822, 523),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final brightness = controller.orionTheme.themeMode == ThemeMode.light
      ? Brightness.light
      : Brightness.dark;
  await tester.pumpWidget(
    MaterialApp(
      theme: orionTheme(
        brightness,
        controller.orionTheme.accent,
        preferences: controller.orionTheme,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: systemReducedMotion),
        child: UiScaleViewport(scale: scale, child: child!),
      ),
      home: Scaffold(
        body: OrionStartupReveal(
          controller: controller,
          onComplete: onComplete,
        ),
      ),
    ),
  );
  await tester.pump();
}
