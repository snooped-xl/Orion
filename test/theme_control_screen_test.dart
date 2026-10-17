import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/models/companion_window.dart';
import 'package:orion/screens/theme_control_screen.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/theme_color_picker.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';
import 'package:orion/widgets/orion_overlay.dart';

class _StudioHost implements CompanionWindowHost {
  final opened = <CompanionWindowKind>[];
  @override
  Future<void> open(CompanionWindowKind kind, {String? documentId}) async =>
      opened.add(kind);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'RobotoFlex',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-Regular.ttf'))).load();
  });

  Future<void> mount(
    WidgetTester tester,
    OrionController c, {
    Size size = const Size(700, 450),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: c,
        builder: (context, _) => MaterialApp(
          theme: orionTheme(
            c.themeMode == ThemeMode.light ? Brightness.light : Brightness.dark,
            c.orionTheme.accent,
            preferences: c.orionTheme,
            reducedMotion: c.reducedMotion,
            compactMode: c.orionCompactMode,
          ),
          builder: (context, child) =>
              UiScaleViewport(scale: c.uiScale, child: child!),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: ThemeControlScreen(controller: c),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> cleanup(WidgetTester tester, OrionController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  testWidgets(
    'Theme Control opens generic Studio and keeps existing easy controls',
    (tester) async {
      final c = OrionController(persistChanges: false);
      final host = _StudioHost();
      c.companionWindows = host;
      await mount(tester, c);
      expect(find.text('Theme Studio'), findsOneWidget);
      expect(
        find.text('Advanced Theme Editing, saving, exporting, and more'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('theme-reset')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('orion-theme-studio')));
      await tester.pumpAndSettle();
      expect(host.opened, [CompanionWindowKind.orionThemeStudio]);
      expect(c.orionTheme, OrionThemePreferences.defaults);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'primary presets apply actual global palettes and reset preserves layout',
    (tester) async {
      final c = OrionController(persistChanges: false);
      await mount(tester, c);
      expect(find.text('Orion Expressive'), findsOneWidget);
      expect(find.text('Original Orion'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('theme-preset-original-orion')),
      );
      await tester.pumpAndSettle();
      expect(c.orionTheme.presetId, 'original-orion');
      final colors = OrionColors.of(
        tester.element(find.byType(ThemeControlScreen)),
      );
      expect(colors.panel, const Color(0xff07080a));
      expect(colors.editorColor, const Color(0xff101112));
      final editorPreview = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('theme-preview-editor-original-orion')),
      );
      expect(
        (editorPreview.decoration as BoxDecoration).color,
        Colors.transparent,
      );
      expect(colors.backgroundGradient!.colors, [
        const Color(0xff181a1b),
        const Color(0xff08090a),
      ]);
      tester
          .widget<Slider>(find.byKey(const ValueKey('theme-surface-tint')))
          .onChanged!(.6);
      await tester.pumpAndSettle();
      final tinted = OrionColors.of(
        tester.element(find.byType(ThemeControlScreen)),
      );
      expect(tinted.panel, isNot(colors.panel));
      expect(tinted.editorColor, isNot(colors.editorColor));
      c.setOrionCompactMode(true);
      c.setReducedMotion(true);
      c.setUiScale(1.2);
      c.setOrionTheme(c.orionTheme.copyWith(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('theme-reset')));
      await tester.pumpAndSettle();
      expect(c.orionTheme, OrionThemePreferences.defaults);
      expect(c.orionCompactMode, true);
      expect(c.reducedMotion, true);
      expect(c.uiScale, 1.2);
      await cleanup(tester, c);
    },
  );

  for (final size in [const Size(680, 420), const Size(330, 560)]) {
    testWidgets('Blue Glass preset selects and resets at ${size.width}px', (
      tester,
    ) async {
      final c = OrionController(persistChanges: false)..setReducedMotion(true);
      await mount(tester, c, size: size);
      final card = find.byKey(const ValueKey('theme-preset-blue-glass'));
      await tapVisible(tester, card);
      expect(c.orionTheme.presetId, 'blue-glass');
      expect(c.orionTheme.basePalette, 'liquid-glass');
      expect(c.orionTheme.gradientEnabled, true);
      expect(c.orionTheme.liquidGlassEnabled, true);
      expect(c.orionTheme.windowOpacity, .63);
      final colors = OrionColors.of(
        tester.element(find.byType(ThemeControlScreen)),
      );
      expect(colors.glassEnabled, true);
      expect(colors.backgroundGradient, isNotNull);
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.byKey(const ValueKey('theme-reset')));
      expect(c.orionTheme, OrionThemePreferences.defaults);
      expect(c.reducedMotion, true);
      await cleanup(tester, c);
    });
  }

  testWidgets('hex validation and Cancel never commit a color draft', (
    tester,
  ) async {
    final c = OrionController(persistChanges: false);
    await mount(tester, c);
    final before = c.orionTheme;
    await tapVisible(tester, find.byKey(const ValueKey('theme-accent-custom')));
    await tester.enterText(
      find.byKey(const ValueKey('theme-color-hex')),
      '#nothex',
    );
    await tester.pumpAndSettle();
    expect(find.text('Use 6 or 8 hex digits'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('theme-color-apply')))
          .onPressed,
      isNull,
    );
    expect(c.orionTheme, before);
    await tester.enterText(
      find.byKey(const ValueKey('theme-color-hex')),
      '#27AE91',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.orionTheme, before);
    await tapVisible(tester, find.byKey(const ValueKey('theme-accent-custom')));
    await tester.enterText(
      find.byKey(const ValueKey('theme-color-hex')),
      '#27AE91',
    );
    await tester.tap(find.byKey(const ValueKey('theme-color-apply')));
    await tester.pumpAndSettle();
    expect(c.orionTheme.accent, const Color(0xff27ae91));
    expect(c.orionTheme.presetId, 'custom');
    expect(
      OrionColors.of(tester.element(find.byType(ThemeControlScreen))).accent,
      const Color(0xff27ae91),
    );
    await cleanup(tester, c);
  });

  testWidgets(
    'gradient stops and per-role overrides apply and reset independently',
    (tester) async {
      final c = OrionController(persistChanges: false);
      await mount(tester, c);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('theme-gradient-switch')),
      );
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.byKey(const ValueKey('theme-gradient-add')),
      );
      expect(c.orionTheme.gradientColors.length, 3);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('theme-gradient-stop-1')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('theme-color-hex')),
        '#25354A',
      );
      await tester.tap(find.byKey(const ValueKey('theme-color-apply')));
      await tester.pumpAndSettle();
      expect(c.orionTheme.gradientColors[1], const Color(0xff25354a));
      await tapVisible(tester, find.byTooltip('Remove stop 3'));
      expect(c.orionTheme.gradientColors.length, 2);
      await tapVisible(tester, find.byKey(const ValueKey('theme-fine-tuning')));
      await tapVisible(tester, find.byKey(const ValueKey('theme-role-editor')));
      await tester.enterText(
        find.byKey(const ValueKey('theme-color-hex')),
        '#182433',
      );
      await tester.tap(find.byKey(const ValueKey('theme-color-apply')));
      await tester.pumpAndSettle();
      expect(c.orionTheme.overrides['editor'], const Color(0xff182433));
      expect(
        OrionColors.of(
          tester.element(find.byType(ThemeControlScreen)),
        ).editorColor,
        const Color(0xff182433),
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('theme-reset-role-editor')),
      );
      expect(c.orionTheme.overrides.containsKey('editor'), false);
      expect(c.orionTheme.gradientEnabled, true);
      expect(c.orionTheme.gradientColors[1], const Color(0xff25354a));
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'saved themes apply and delete with JSON export and validated import',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final c = OrionController(persistChanges: false);
      await mount(tester, c);
      await tester.tap(
        find.byKey(const ValueKey('theme-preset-original-orion')),
      );
      await tester.pumpAndSettle();
      final original = c.orionTheme;
      await tester.tap(find.byTooltip('Save current theme'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('theme-save-name')),
        'My graphite',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('theme-save-confirm')));
      await tester.pumpAndSettle();
      expect(c.savedOrionThemes.single.name, 'My graphite');
      await tester.tap(find.byKey(const ValueKey('theme-reset')));
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.byKey(const ValueKey('theme-saved-themes')),
      );
      await tapVisible(
        tester,
        find.byKey(ValueKey('theme-saved-${c.savedOrionThemes.single.id}')),
      );
      expect(c.orionTheme, original);
      await tapVisible(tester, find.text('Export JSON'));
      expect(jsonDecode(copied!), c.orionTheme.toJson());
      await tapVisible(tester, find.text('Import').first);
      await tester.enterText(
        find.byKey(const ValueKey('theme-import-json')),
        '{broken',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid Orion theme'), findsOneWidget);
      expect(c.orionTheme, original);
      await tester.enterText(
        find.byKey(const ValueKey('theme-import-json')),
        jsonEncode(OrionThemePreferences.defaults.toJson()),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();
      expect(c.orionTheme, OrionThemePreferences.defaults);
      await tapVisible(tester, find.byTooltip('Delete My graphite'));
      expect(c.savedOrionThemes, isEmpty);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'layout controls keep scale stable while dragging and apply keyboard changes',
    (tester) async {
      final c = OrionController(persistChanges: false);
      await mount(tester, c);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('theme-layout-controls')),
      );
      final slider = find.byKey(const ValueKey('ui-scale-slider'));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final rect = tester.getRect(slider);
      final gesture = await tester.startGesture(
        Offset(rect.left + rect.width * .45, rect.center.dy),
      );
      await gesture.moveTo(Offset(rect.right - 20, rect.center.dy));
      await tester.pump();
      expect(c.uiScale, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(c.uiScale, greaterThan(1));
      final before = c.uiScale;
      tester.widget<Slider>(slider).onChanged!(.8);
      await tester.pumpAndSettle();
      expect(c.uiScale, .8);
      expect(c.uiScale, isNot(before));
      await tapVisible(tester, find.text('Light'));
      expect(c.themeMode, ThemeMode.light);
      expect(find.text('Compact mode'), findsNothing);
      expect(find.text('Enlarged mode'), findsNothing);
      await tapVisible(tester, find.text('Reduce motion'));
      expect(c.reducedMotion, true);
      await cleanup(tester, c);
    },
  );

  testWidgets('theme controls and color dialog fit compact scaled windows', (
    tester,
  ) async {
    for (final scale in [.8, 1.0, 1.25]) {
      final c = OrionController(persistChanges: false)..setUiScale(scale);
      await mount(tester, c, size: const Size(680, 420));
      final before = c.orionTheme;
      expect(tester.takeException(), isNull, reason: 'Theme at $scale');
      await tapVisible(
        tester,
        find.byKey(const ValueKey('theme-accent-custom')),
      );
      await tester.tap(find.byKey(const ValueKey('theme-color-plane')));
      await tester.pumpAndSettle();
      final hexInput = tester.widget<TextField>(
        find.byKey(const ValueKey('theme-color-hex')),
      );
      expect(hexInput.controller!.text, isNot('#88B5FF'));
      tester
          .widget<Slider>(find.byKey(const ValueKey('theme-hue-slider')))
          .onChanged!(120);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('theme-hue-slider')))
            .value,
        120,
      );
      expect(c.orionTheme, before);
      expect(find.byType(ThemeColorPicker), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Picker at $scale');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      for (final key in [
        'theme-fine-tuning',
        'theme-saved-themes',
        'theme-layout-controls',
        'theme-branding',
      ]) {
        await tapVisible(tester, find.byKey(ValueKey(key)));
        expect(tester.takeException(), isNull, reason: '$key at $scale');
      }
      await cleanup(tester, c);
    }
  });
  testWidgets(
    'five default presets retain compact cards and Rain remains customizable',
    (tester) async {
      final c = OrionController(persistChanges: false);
      await mount(tester, c, size: const Size(680, 420));
      final expressive = find.byKey(const ValueKey('theme-preset-expressive'));
      final classic = find.byKey(const ValueKey('theme-preset-original-orion'));
      final rain = find.byKey(const ValueKey('theme-preset-material-rain'));
      final glass = find.byKey(const ValueKey('theme-preset-liquid-glass'));
      final blueGlass = find.byKey(const ValueKey('theme-preset-blue-glass'));
      expect(find.text('Material Rain'), findsOneWidget);
      expect(find.text('Blue Glass'), findsOneWidget);
      expect(tester.getSize(blueGlass), tester.getSize(glass));
      expect(tester.getTopLeft(blueGlass).dx, tester.getTopLeft(expressive).dx);
      expect(
        tester.getTopLeft(blueGlass).dy,
        greaterThan(tester.getTopLeft(glass).dy),
      );
      expect(tester.getTopLeft(expressive).dy, tester.getTopLeft(classic).dy);
      expect(tester.getTopLeft(rain).dy, tester.getTopLeft(glass).dy);
      expect(
        tester.getTopLeft(rain).dy,
        greaterThan(tester.getTopLeft(expressive).dy),
      );
      expect(tester.getTopLeft(rain).dx, tester.getTopLeft(expressive).dx);
      expect(tester.getTopLeft(glass).dx, tester.getTopLeft(classic).dx);
      await tester.tap(rain);
      await tester.pumpAndSettle();
      expect(c.orionTheme.presetId, 'material-rain');
      expect(c.orionTheme.rainEnabled, true);
      expect(c.orionTheme.windowOpacity, .9);
      expect(c.orionTheme.gradientEnabled, false);
      tester
          .widget<Slider>(find.byKey(const ValueKey('theme-surface-tint')))
          .onChanged!(.2);
      await tester.pumpAndSettle();
      expect(c.orionTheme.rainEnabled, true);
      expect(c.orionTheme.windowOpacity, .9);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('theme-layout-controls')),
      );
      await tapVisible(tester, find.text('Rain effect'));
      expect(c.orionTheme.rainEnabled, false);
      tester
          .widget<Slider>(find.byKey(const ValueKey('theme-window-opacity')))
          .onChanged!(.82);
      await tester.pumpAndSettle();
      expect(c.orionTheme.windowOpacity, .82);
      expect(c.orionTheme.basePalette, 'material-rain');
      await tapVisible(tester, find.byKey(const ValueKey('theme-reset')));
      expect(c.orionTheme, OrionThemePreferences.defaults);
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'save and import dialogs follow the live palette without discarding drafts',
    (tester) async {
      final c = OrionController(persistChanges: false);
      c.setOrionTheme(OrionThemePreferences.builtInPresets[1].preferences);
      await mount(tester, c);
      await tapVisible(tester, find.byTooltip('Save current theme'));
      await tester.enterText(
        find.byKey(const ValueKey('theme-save-name')),
        'My draft name',
      );
      await tester.pumpAndSettle();
      BoxDecoration surface() =>
          tester
                  .widget<AnimatedContainer>(
                    find.byKey(const ValueKey('orion-overlay-decoration')),
                  )
                  .decoration!
              as BoxDecoration;
      expect(find.byType(OrionOverlayTheme), findsOneWidget);
      expect(surface().gradient, isNotNull);
      c.setOrionTheme(OrionThemePreferences.builtInPresets[2].preferences);
      await tester.pumpAndSettle();
      expect(surface().gradient, isNull);
      expect(surface().color, const Color(0xFF101113));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('theme-save-name')))
            .controller!
            .text,
        'My draft name',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.byKey(const ValueKey('theme-saved-themes')),
      );
      await tapVisible(tester, find.text('Import').first);
      await tester.enterText(
        find.byKey(const ValueKey('theme-import-json')),
        '{draft',
      );
      c.setOrionTheme(OrionThemePreferences.builtInPresets[1].preferences);
      await tester.pumpAndSettle();
      expect(surface().gradient, isNotNull);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('theme-import-json')))
            .controller!
            .text,
        '{draft',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );
}
