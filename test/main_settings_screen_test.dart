import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/screens/settings_screen.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'RobotoFlex',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-Regular.ttf'))).load();
  });

  Future<void> mount(
    WidgetTester tester,
    OrionController controller, {
    double scale = 1,
    Size size = const Size(822, 523),
    VoidCallback? onReplayIntro,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: orionTheme(
          Brightness.dark,
          controller.orionTheme.accent,
          preferences: controller.orionTheme,
          reducedMotion: true,
        ),
        builder: (context, child) =>
            UiScaleViewport(scale: scale, child: child!),
        home: Scaffold(
          body: Padding(
            // Reserve the same header and rail space as the main Orion shell.
            padding: const EdgeInsets.fromLTRB(100, 68, 16, 16),
            child: SettingsScreen(
              controller: controller,
              onReplayIntro: onReplayIntro ?? () {},
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

  Finder preference(String key) => find.byKey(ValueKey('settings-$key'));

  testWidgets('settings edits synchronize through exported window state', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false);
    final restored = OrionController(persistChanges: false);
    try {
      await mount(tester, controller);
      final toggles = <(String, bool Function())>[
        ('always-on-top', () => controller.alwaysOnTop),
        ('minimap', () => controller.showMinimap),
        ('line-numbers', () => controller.showLineNumbers),
        ('word-wrap', () => controller.wordWrap),
        ('autocomplete', () => controller.autocomplete),
        ('bracket-colors', () => controller.bracketPairColorization),
        ('whitespace', () => controller.renderWhitespace),
      ];
      for (final (key, value) in toggles) {
        final before = value();
        await tapVisible(tester, preference(key));
        expect(value(), !before, reason: key);
        expect(tester.widget<Switch>(preference(key)).value, !before);
      }
      final font = preference('editor-font-size');
      await tester.ensureVisible(font);
      await tester.pumpAndSettle();
      final rect = tester.getRect(font);
      await tester.tapAt(Offset(rect.left + rect.width * .75, rect.center.dy));
      await tester.pumpAndSettle();
      expect(controller.editorFontSize, greaterThan(14));
      await tester.pumpWidget(const SizedBox.shrink());
      restored.applyWindowState(controller.exportWindowState());
      expect(restored.alwaysOnTop, controller.alwaysOnTop);
      expect(restored.showMinimap, controller.showMinimap);
      expect(restored.showLineNumbers, controller.showLineNumbers);
      expect(restored.wordWrap, controller.wordWrap);
      expect(restored.autocomplete, controller.autocomplete);
      expect(
        restored.bracketPairColorization,
        controller.bracketPairColorization,
      );
      expect(restored.renderWhitespace, controller.renderWhitespace);
      expect(restored.editorFontSize, controller.editorFontSize);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      restored.dispose();
    }
  });

  testWidgets('Linux settings expose the Relapse switch and launcher controls', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false);
    try {
      await mount(tester, controller);
      if (!controller.relapseSupportAvailable) {
        expect(find.text('Relapse support'), findsNothing);
        return;
      }
      final toggle = preference('relapse-support');
      expect(toggle, findsOneWidget);
      expect(controller.relapseSupportEnabled, isFalse);
      // The launcher row only appears while Relapse support is enabled.
      expect(
        find.byKey(const ValueKey('settings-relapse-launch')),
        findsNothing,
      );
      await tapVisible(tester, toggle);
      expect(controller.relapseSupportEnabled, isTrue);
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(
        find.byKey(const ValueKey('settings-relapse-launch')),
        findsOneWidget,
      );
      expect(find.text('Select executable'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-relapse-change-launcher')),
        findsNothing,
      );

      // RelapseGtk's "Redirect script output" switch, mirrored here.
      final redirect = preference('relapse-output-redirect');
      expect(redirect, findsOneWidget);
      expect(controller.relapseOutputRedirect, isTrue);
      await tapVisible(tester, redirect);
      expect(controller.relapseOutputRedirect, isFalse);
      expect(tester.widget<Switch>(redirect).value, isFalse);

      // A chosen launcher swaps the picker for Launch/Change controls.
      controller.applyWindowState({
        ...controller.exportWindowState(),
        'relapseLauncherPath': '/opt/relapse/relapse-gtk',
      });
      await tester.pumpAndSettle();
      expect(find.text('Launch Relapse'), findsOneWidget);
      expect(find.text('Select executable'), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-relapse-change-launcher')),
        findsOneWidget,
      );
      expect(
        find.text('relapse-gtk · /opt/relapse/relapse-gtk'),
        findsOneWidget,
      );

      // Launcher problems surface inline instead of failing silently.
      controller.applyWindowState({
        ...controller.exportWindowState(),
        'relapseLauncherError': 'The selected launcher no longer exists.',
      });
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-relapse-launcher-error')),
        findsOneWidget,
      );
      expect(
        find.text('The selected launcher no longer exists.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  for (final glassy in [false, true]) {
    for (final scale in [.8, 1.0, 1.25]) {
      testWidgets(
        '${glassy ? 'Glassy' : 'Expressive'} settings remain usable in a compact window at $scale scale',
        (tester) async {
          final controller = OrionController(persistChanges: false);
          if (glassy) {
            controller.setOrionTheme(
              OrionThemePreferences.builtInPresets
                  .singleWhere((preset) => preset.id == 'liquid-glass')
                  .preferences,
            );
          }
          var replayed = false;
          try {
            await mount(
              tester,
              controller,
              scale: scale,
              size: const Size(720, 480),
              onReplayIntro: () => replayed = true,
            );
            expect(tester.takeException(), isNull);
            await tapVisible(tester, find.text('Always on top'));
            expect(controller.alwaysOnTop, isTrue);
            final minimapBefore = controller.showMinimap;
            await tapVisible(tester, preference('minimap'));
            expect(controller.showMinimap, !minimapBefore);
            await tapVisible(tester, preference('local-recovery'));
            expect(controller.autosave, isFalse);
            expect(find.text('Ctrl + Space'), findsOneWidget);
            await tapVisible(tester, find.text('Replay intro'));
            expect(replayed, isTrue);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
          }
        },
      );
    }
  }
}
