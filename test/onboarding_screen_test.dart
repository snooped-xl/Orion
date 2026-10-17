import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/screens/onboarding_screen.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/orion_logo.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('RobotoFlex')
          ..addFont(rootBundle.load('assets/fonts/RobotoFlex-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/RobotoFlex-Medium.ttf'))
          ..addFont(rootBundle.load('assets/fonts/RobotoFlex-Semibold.ttf')))
        .load();
  });

  Future<void> mount(
    WidgetTester tester,
    OrionController controller, {
    VoidCallback? onComplete,
    Future<bool> Function()? onSaveBridge,
    Future<void> Function()? onCopyBridge,
    Future<void> Function()? onOpenBridgeFolder,
    Size size = const Size(822, 523),
    double scale = 1,
    bool systemReducedMotion = false,
    Key? introKey,
    double topInset = 52,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: orionTheme(
          controller.orionTheme.themeMode == ThemeMode.light
              ? Brightness.light
              : Brightness.dark,
          controller.accentColor,
          preferences: controller.orionTheme,
          reducedMotion: controller.reducedMotion,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: systemReducedMotion),
          child: UiScaleViewport(scale: scale, child: child!),
        ),
        home: Scaffold(
          body: Padding(
            // The window title bar remains available above the tutorial.
            padding: EdgeInsets.only(top: topInset),
            child: OrionOnboardingScreen(
              key: introKey,
              controller: controller,
              onComplete: onComplete ?? () {},
              onSaveBridge: onSaveBridge ?? () async => true,
              onCopyBridge: onCopyBridge ?? () async {},
              onOpenBridgeFolder: onOpenBridgeFolder ?? () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('introduction waits for the user and completes only at the end', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false);
    addTearDown(controller.dispose);
    var completions = 0;
    await mount(tester, controller, onComplete: () => completions++);
    expect(find.text('Welcome to Orion'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-back')), findsNothing);
    await tester.pump(const Duration(seconds: 12));
    expect(completions, 0);
    expect(controller.introCompleted, isFalse);
    await next(tester);
    expect(find.text('Connect your executor'), findsOneWidget);
    expect(find.textContaining('autoexecute folder'), findsOneWidget);
    await tapVisible(tester, 'onboarding-back');
    expect(find.text('Welcome to Orion'), findsOneWidget);
    await next(tester);
    await next(tester);
    expect(find.text('Smoother starts'), findsOneWidget);
    expect(find.textContaining('Turn on auto attach'), findsOneWidget);
    await next(tester);
    expect(find.text('Executor Quick Launch'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(completions, 0);
    await next(tester);
    expect(completions, 1);
    await next(tester);
    expect(completions, 1);
    // Only the shell commits completion, so replay cannot modify persistence.
    expect(controller.introCompleted, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'bridge actions distinguish a canceled save from successful work',
    (tester) async {
      final controller = OrionController(persistChanges: false);
      addTearDown(controller.dispose);
      var saves = 0;
      var copies = 0;
      var folders = 0;
      await mount(
        tester,
        controller,
        onSaveBridge: () async => ++saves > 1,
        onCopyBridge: () async => copies++,
        onOpenBridgeFolder: () async => folders++,
      );
      await next(tester);
      await tapVisible(tester, 'onboarding-save-bridge');
      expect(saves, 1);
      expect(find.byKey(const ValueKey('onboarding-feedback')), findsNothing);
      await tapVisible(tester, 'onboarding-save-bridge');
      expect(saves, 2);
      expect(find.textContaining('Bridge script saved.'), findsOneWidget);
      await tapVisible(tester, 'onboarding-copy-bridge');
      expect(copies, 1);
      expect(find.text('Bridge script copied.'), findsOneWidget);
      await tapVisible(tester, 'onboarding-open-bridge-folder');
      expect(folders, 1);
      expect(find.text('Bridge folder opened.'), findsOneWidget);
      await next(tester);
      expect(find.byKey(const ValueKey('onboarding-feedback')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('file errors are concise and retry remains usable', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false);
    addTearDown(controller.dispose);
    var attempt = 0;
    await mount(
      tester,
      controller,
      onSaveBridge: () async {
        if (++attempt == 1) throw StateError('/private/path/with-details');
        return true;
      },
    );
    await next(tester);
    await tapVisible(tester, 'onboarding-save-bridge');
    expect(
      find.text('Couldn’t save the Bridge script. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('/private/path'), findsNothing);
    await tapVisible(tester, 'onboarding-save-bridge');
    expect(attempt, 2);
    expect(find.textContaining('Bridge script saved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a pending bridge action blocks navigation and survives disposal',
    (tester) async {
      final controller = OrionController(persistChanges: false);
      addTearDown(controller.dispose);
      final pendingSave = Completer<bool>();
      await mount(tester, controller, onSaveBridge: () => pendingSave.future);
      await next(tester);
      await tester.tap(find.byKey(const ValueKey('onboarding-save-bridge')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('onboarding-next')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('onboarding-back')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('onboarding-copy-bridge')),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      pendingSave.complete(true);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  for (final system in [false, true]) {
    testWidgets(
      '${system ? 'system' : 'preference'} reduced motion changes pages immediately',
      (tester) async {
        final controller = OrionController(persistChanges: false);
        addTearDown(controller.dispose);
        if (!system) controller.setReducedMotion(true);
        await mount(tester, controller, systemReducedMotion: system);
        await tester.tap(find.byKey(const ValueKey('onboarding-next')));
        await tester.pump();
        expect(find.text('Connect your executor'), findsOneWidget);
        expect(find.text('Welcome to Orion'), findsNothing);
        expect(
          find.byKey(const ValueKey('onboarding-outgoing-page')),
          findsNothing,
        );
        expect(
          tester
              .widget<FractionallySizedBox>(
                find.byKey(const ValueKey('onboarding-progress-1')),
              )
              .widthFactor,
          1,
        );
        // Material's button ink may finish independently of page motion.
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('all palettes and a custom light theme fit enlarged compact UI', (
    tester,
  ) async {
    final themes = [
      for (final preset in OrionThemePreferences.builtInPresets.take(4))
        preset.preferences,
      OrionThemePreferences(
        presetId: 'custom-tutorial',
        themeMode: ThemeMode.light,
        accent: const Color(0xFF34734B),
        gradientEnabled: true,
        gradientColors: const [Color(0xFFE6F4E9), Color(0xFFFFF7DE)],
        overrides: const {'ink': Color(0xFF192B1E)},
      ),
    ];
    for (var index = 0; index < themes.length; index++) {
      final controller = OrionController(persistChanges: false);
      controller.setOrionTheme(themes[index]);
      controller.setReducedMotion(true);
      var completed = false;
      try {
        await mount(
          tester,
          controller,
          introKey: ValueKey(index),
          size: const Size(680, 420),
          scale: 1.25,
          onComplete: () => completed = true,
        );
        final heading = tester.widget<Text>(find.text('Welcome to Orion'));
        final context = tester.element(find.byType(OrionOnboardingScreen));
        final colors = OrionColors.of(context);
        expect(heading.style!.color, colors.ink);
        for (var step = 0; step < 4; step++) {
          if (step == 1) {
            await tapVisible(tester, 'onboarding-save-bridge');
            expect(find.textContaining('Bridge script saved.'), findsOneWidget);
          }
          final nextRect = tester.getRect(
            find.byKey(const ValueKey('onboarding-next')),
          );
          expect(nextRect.bottom, lessThanOrEqualTo(420));
          expect(nextRect.top, greaterThanOrEqualTo(0));
          expect(
            tester.takeException(),
            isNull,
            reason: themes[index].presetId,
          );
          await next(tester);
        }
        expect(completed, isTrue);
        expect(tester.takeException(), isNull, reason: themes[index].presetId);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    }
  });

  testWidgets('compact Bridge setup shows every file action before scrolling', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false);
    addTearDown(controller.dispose);
    await mount(tester, controller, size: const Size(680, 378), topInset: 0);
    await next(tester);
    final footerTop = tester
        .getTopLeft(find.byKey(const ValueKey('onboarding-next')))
        .dy;
    for (final action in ['save-bridge', 'copy-bridge', 'open-bridge-folder']) {
      final finder = find.byKey(ValueKey('onboarding-$action'));
      expect(finder.hitTestable(), findsOneWidget, reason: action);
      expect(tester.getBottomRight(finder).dy, lessThan(footerTop));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'welcome uses the chosen logo instead of assuming the stock art',
    (tester) async {
      final controller = OrionController(persistChanges: false);
      addTearDown(controller.dispose);
      final logo = await rootBundle.load('assets/branding/orion-wordmark.png');
      controller.setCustomLogo(logo.buffer.asUint8List());
      await mount(tester, controller);
      final wordmark = tester.widget<OrionWordmark>(find.byType(OrionWordmark));
      expect(wordmark.customImage, controller.customLogoBytes);
      expect(find.bySemanticsLabel('Custom Orion logo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
