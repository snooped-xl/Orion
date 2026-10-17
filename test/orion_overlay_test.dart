import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:orion/app.dart';
import 'package:orion/widgets/theme_color_picker.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/orion_overlay.dart';

BoxDecoration _decoration(WidgetTester tester) =>
    tester
            .widget<AnimatedContainer>(
              find.byKey(const ValueKey('orion-overlay-decoration')),
            )
            .decoration!
        as BoxDecoration;
OrionColors _colors(WidgetTester tester) =>
    OrionColors.of(tester.element(find.byType(OrionOverlaySurface)));

Future<void> _mount(WidgetTester tester, OrionController c, {Widget? child}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        ),
        home: Scaffold(
          body: OrionOverlayTheme(
            controller: c,
            builder: (context) => OrionOverlaySurface(
              child:
                  child ??
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Overlay title',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Overlay detail',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Icon(
                        Icons.devices,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'Easy theme carries its accent and gradient into overlay chrome',
    (tester) async {
      final c = OrionController(persistChanges: false)
        ..setReducedMotion(true)
        ..setOrionTheme(
          OrionThemePreferences(
            presetId: 'custom',
            accent: const Color(0xffe6ad79),
            gradientEnabled: true,
            gradientColors: const [
              Color(0xff131b17),
              Color(0xff30211c),
              Color(0xff171523),
            ],
            gradientStops: const [0, .4, 1],
            gradientAngle: 75,
          ),
        );
      await _mount(tester, c);
      final colors = _colors(tester), decoration = _decoration(tester);
      expect(colors.accent, const Color(0xffe6ad79));
      expect(decoration.gradient, orionOverlayGradient(colors));
      expect(
        decoration.gradient!.colors,
        isNot(equals(colors.backgroundGradient!.colors)),
      );
      expect((decoration.gradient! as LinearGradient).stops, [0, .4, 1]);
      expect(decoration.color, colors.elevated);
      expect(
        tester.widget<Text>(find.text('Overlay title')).style!.color,
        colors.ink,
      );
      expect(
        tester.widget<Text>(find.text('Overlay detail')).style!.color,
        colors.muted,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.devices)).color,
        colors.readableAccent,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('Original Orion keeps its neutral gradient and fine outlines', (
    tester,
  ) async {
    final classic = OrionThemePreferences.builtInPresets
        .singleWhere((p) => p.id == 'original-orion')
        .preferences;
    final c = OrionController(persistChanges: false)
      ..setReducedMotion(true)
      ..setOrionTheme(classic);
    await _mount(tester, c);
    final colors = _colors(tester), decoration = _decoration(tester);
    expect(decoration.gradient, colors.backgroundGradient);
    expect(decoration.border!.top.width, .67);
    expect(decoration.border!.top.color, colors.outline(.6));
    for (final color in [
      colors.accent,
      colors.ink,
      colors.muted,
      ...decoration.gradient!.colors,
    ]) {
      expect(
        [color.r, color.g, color.b].reduce(math.max) -
            [color.r, color.g, color.b].reduce(math.min),
        lessThan(.03),
      );
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'Fine elevated and border choices override a generated overlay gradient',
    (tester) async {
      const elevated = Color(0xff26362f), border = Color(0xffb8a49c);
      final c = OrionController(persistChanges: false)
        ..setReducedMotion(true)
        ..setOrionTheme(
          OrionThemePreferences(
            gradientEnabled: true,
            overrides: const {
              'elevated': elevated,
              'border': border,
              'ink': Color(0xfffafcf8),
              'muted': Color(0xffdadac7),
            },
          ),
        );
      await _mount(tester, c);
      final colors = _colors(tester), decoration = _decoration(tester);
      expect(decoration.color, elevated);
      expect(decoration.gradient, isNull);
      expect(colors.border, border);
      expect(decoration.border!.top.color, colors.outline(.4));
      expect(
        tester.widget<Text>(find.text('Overlay title')).style!.color,
        colors.ink,
      );
      expect(
        tester.widget<Text>(find.text('Overlay detail')).style!.color,
        colors.muted,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'an open overlay tracks palette and light mode without losing drafts',
    (tester) async {
      final c = OrionController(persistChanges: false)..setReducedMotion(true);
      final input = TextEditingController(text: 'draft survives');
      await _mount(
        tester,
        c,
        child: TextField(key: const ValueKey('draft'), controller: input),
      );
      final first = _colors(tester).accent;
      c.setOrionTheme(
        OrionThemePreferences(
          themeMode: ThemeMode.light,
          accent: const Color(0xffa74c75),
          gradientEnabled: true,
          gradientColors: const [Color(0xfff2ebe0), Color(0xffe8edf5)],
        ),
      );
      await tester.pumpAndSettle();
      final colors = _colors(tester);
      expect(colors.accent, isNot(first));
      expect(colors.accent, const Color(0xffa74c75));
      expect(colors.isLight, true);
      expect(_decoration(tester).gradient, orionOverlayGradient(colors));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('draft')))
            .controller!
            .text,
        'draft survives',
      );
      await tester.pumpWidget(const SizedBox());
      input.dispose();
      c.dispose();
    },
  );

  testWidgets(
    'system brightness and reduced motion propagate into overlay controls',
    (tester) async {
      final c = OrionController(persistChanges: false)
        ..setReducedMotion(true)
        ..setThemeMode(ThemeMode.system);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _mount(tester, c);
      expect(_colors(tester).isLight, false);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(_colors(tester).isLight, true);
      final surface = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('orion-overlay-decoration')),
      );
      final animatedTheme = tester.widget<AnimatedTheme>(
        find
            .descendant(
              of: find.byType(OrionOverlayTheme),
              matching: find.byType(AnimatedTheme),
            )
            .first,
      );
      expect(surface.duration, Duration.zero);
      expect(animatedTheme.duration, Duration.zero);
      expect(
        MediaQuery.disableAnimationsOf(
          tester.element(find.byType(OrionOverlaySurface)),
        ),
        true,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'editor menu, rename, clear and command palette stay themed while open',
    (tester) async {
      tester.view.physicalSize = const Size(822, 523);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = OrionController(persistChanges: false)
        ..setReducedMotion(true)
        ..completeIntro();
      c.updateDocumentContent(c.activeDocumentId, 'print("preserved")');
      final classic = OrionThemePreferences.builtInPresets
          .singleWhere((p) => p.id == 'original-orion')
          .preferences;
      final rain = OrionThemePreferences.builtInPresets
          .singleWhere((p) => p.id == 'material-rain')
          .preferences
          .copyWith(rainEnabled: false);
      await tester.pumpWidget(OrionApp(controller: c, nativeWindow: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Editor actions'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('orion-popup-menu')), findsOneWidget);
      c.setOrionTheme(classic);
      await tester.pumpAndSettle();
      var menuColors = OrionColors.of(
        tester.element(find.byKey(const ValueKey('orion-popup-menu'))),
      );
      expect(menuColors.accent, OrionThemePreferences.originalAccent);
      expect(_decoration(tester).gradient, menuColors.backgroundGradient);
      c.setOrionTheme(rain);
      await tester.pumpAndSettle();
      menuColors = OrionColors.of(
        tester.element(find.byKey(const ValueKey('orion-popup-menu'))),
      );
      expect(menuColors.accent, OrionThemePreferences.materialRainAccent);
      expect(_decoration(tester).color, menuColors.elevated);
      await tester.tap(find.text('Rename script'));
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, 'retained-name.lua');
      c.setOrionTheme(classic);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input).controller!.text,
        'retained-name.lua',
      );
      expect(_decoration(tester).gradient, _colors(tester).backgroundGradient);
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(c.activeDocument.name, 'retained-name.lua');
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      c.setOrionTheme(rain);
      await tester.pumpAndSettle();
      expect(_colors(tester).accent, OrionThemePreferences.materialRainAccent);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.activeDocument.content, 'print("preserved")');
      await tester.tap(find.byKey(const ValueKey('code-editor')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final search = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Search actions',
      );
      await tester.enterText(search, 'library');
      c.setOrionTheme(classic);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(search).controller?.text ??
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: search,
                    matching: find.byType(EditableText),
                  ),
                )
                .controller
                .text,
        'library',
      );
      expect(_colors(tester).accent, OrionThemePreferences.originalAccent);
      expect(_decoration(tester).gradient, _colors(tester).backgroundGradient);
      expect(find.widgetWithText(ListTile, 'Script library'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'color picker chrome tracks the palette without changing its color draft',
    (tester) async {
      final c = OrionController(persistChanges: false)..setReducedMotion(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showThemeColorPicker(
                  context,
                  color: const Color(0xff6dba91),
                  title: 'Choose accent',
                  controller: c,
                ),
                child: const Text('Pick'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      final hex = find.byKey(const ValueKey('theme-color-hex'));
      await tester.enterText(hex, '#E4B67F');
      c.setOrionTheme(
        OrionThemePreferences.builtInPresets
            .singleWhere((p) => p.id == 'original-orion')
            .preferences,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(hex).controller!.text, '#E4B67F');
      expect(_colors(tester).accent, OrionThemePreferences.originalAccent);
      expect(_decoration(tester).gradient, _colors(tester).backgroundGradient);
      final preview =
          tester
                  .widget<Container>(
                    find.byKey(const ValueKey('theme-color-preview')),
                  )
                  .decoration!
              as BoxDecoration;
      expect(preview.color, const Color(0xffe4b67f));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
