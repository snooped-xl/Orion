import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/screens/onboarding_screen.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

const _next = ValueKey('onboarding-next');
const _back = ValueKey('onboarding-back');
const _incoming = ValueKey('onboarding-incoming-page');
const _outgoing = ValueKey('onboarding-outgoing-page');

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
    Size size = const Size(822, 523),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: controller,
        builder: (context, _) => MaterialApp(
          theme: orionTheme(
            controller.orionTheme.themeMode == ThemeMode.light
                ? Brightness.light
                : Brightness.dark,
            controller.accentColor,
            preferences: controller.orionTheme,
            reducedMotion: controller.reducedMotion,
          ),
          builder: (context, child) =>
              UiScaleViewport(scale: scale, child: child!),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(top: 52),
              child: OrionOnboardingScreen(
                controller: controller,
                onComplete: onComplete ?? () {},
                onSaveBridge: onSaveBridge ?? () async => true,
                onCopyBridge: () async {},
                onOpenBridgeFolder: () async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> navigate(
    WidgetTester tester,
    Key key, {
    Duration elapsed = const Duration(milliseconds: 70),
  }) async {
    await tester.tap(find.byKey(key));
    await tester.pump();
    await tester.pump(elapsed);
  }

  testWidgets('page motion leaves progress and navigation anchored', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false);
    addTearDown(controller.dispose);
    await mount(tester, controller);
    final headingRect = tester.getRect(find.text('Getting started'));
    final nextRect = tester.getRect(find.byKey(_next));
    final stageRect = tester.getRect(
      find.byKey(const ValueKey('onboarding-page-stage')),
    );

    await navigate(tester, _next);
    expect(find.byKey(_outgoing), findsOneWidget);
    expect(find.byKey(_incoming), findsOneWidget);
    final earlyPosition = tester.getTopLeft(find.text('Connect your executor'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      tester.getTopLeft(find.text('Connect your executor')),
      isNot(earlyPosition),
      reason: 'The incoming content should settle spatially, not only fade.',
    );
    expect(tester.getRect(find.text('Getting started')), headingRect);
    expect(tester.getRect(find.byKey(_next)), nextRect);
    expect(
      tester.getRect(find.byKey(const ValueKey('onboarding-page-stage'))),
      stageRect,
    );

    await tester.pumpAndSettle();
    expect(find.byKey(_outgoing), findsNothing);
    expect(find.text('Welcome to Orion'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'departing Bridge actions cannot receive pointer or accessibility input',
    (tester) async {
      final controller = OrionController(persistChanges: false);
      addTearDown(controller.dispose);
      final semantics = tester.ensureSemantics();
      var saves = 0;
      try {
        await mount(
          tester,
          controller,
          onSaveBridge: () async {
            saves++;
            return true;
          },
        );
        await navigate(tester, _next);
        await tester.pumpAndSettle();
        final save = find.byKey(const ValueKey('onboarding-save-bridge'));
        expect(save.hitTestable(), findsOneWidget);
        expect(find.semantics.byLabel('Save script'), findsOne);

        await navigate(tester, _next);
        expect(find.byKey(_outgoing), findsOneWidget);
        expect(
          save,
          findsOneWidget,
          reason: 'The departing page still paints.',
        );
        expect(save.hitTestable(), findsNothing);
        // Follow the accessibility root rather than cached debug semantics on
        // a RenderObject that has just moved into the outgoing viewport.
        expect(find.semantics.byLabel('Save script'), findsNothing);
        expect(
          find.ancestor(
            of: save,
            matching: find.byWidgetPredicate(
              (widget) => widget is ExcludeFocus && widget.excluding,
            ),
          ),
          findsWidgets,
        );
        await tester.tapAt(tester.getCenter(save));
        await tester.pumpAndSettle();
        expect(saves, 0);
        expect(find.text('Smoother starts'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('Bridge feedback leaves with its page without recentering', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false);
    addTearDown(controller.dispose);
    await mount(tester, controller);
    await navigate(tester, _next);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding-copy-bridge')));
    await tester.pumpAndSettle();
    expect(find.text('Bridge script copied.'), findsOneWidget);
    final beforeHeading = tester.getTopLeft(find.text('Connect your executor'));
    final beforeFeedback = tester.getTopLeft(
      find.text('Bridge script copied.'),
    );

    await tester.tap(find.byKey(_next));
    await tester.pump();
    final outgoing = find.byKey(_outgoing);
    final heading = find.descendant(
      of: outgoing,
      matching: find.text('Connect your executor'),
    );
    final feedback = find.descendant(
      of: outgoing,
      matching: find.text('Bridge script copied.'),
    );
    expect(feedback, findsOneWidget);
    expect(
      (tester.getTopLeft(heading) - beforeHeading).distance,
      lessThan(.01),
      reason: 'Clearing the next page’s feedback must not recenter its exit.',
    );
    expect(
      (tester.getTopLeft(feedback) - beforeFeedback).distance,
      lessThan(.01),
    );
    expect(
      find.ancestor(of: feedback, matching: find.byType(ExcludeSemantics)),
      findsWidgets,
    );
    await tester.pump(const Duration(milliseconds: 90));
    expect(feedback, findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Bridge script copied.'), findsNothing);
    expect(find.text('Connect your executor'), findsNothing);
    expect(find.text('Smoother starts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scrolled compact pages preserve their viewport while departing',
    (tester) async {
      final controller = OrionController(persistChanges: false);
      addTearDown(controller.dispose);
      await mount(tester, controller, size: const Size(680, 420), scale: 1.25);
      await navigate(tester, _next);
      await tester.pumpAndSettle();
      final currentScroll = find.descendant(
        of: find.byKey(_incoming),
        matching: find.byType(Scrollable),
      );
      final beforeState = tester.state<ScrollableState>(currentScroll);
      expect(beforeState.position.maxScrollExtent, greaterThan(0));
      await tester.drag(currentScroll, const Offset(0, -150));
      await tester.pumpAndSettle();
      final beforeOffset = beforeState.position.pixels;
      final beforeHeading = tester.getTopLeft(
        find.text('Connect your executor'),
      );
      expect(beforeOffset, greaterThan(0));

      await tester.tap(find.byKey(_next));
      await tester.pump();
      final outgoingScroll = find.descendant(
        of: find.byKey(_outgoing),
        matching: find.byType(Scrollable),
      );
      final afterState = tester.state<ScrollableState>(outgoingScroll);
      expect(afterState, same(beforeState));
      expect(afterState.position.pixels, closeTo(beforeOffset, .01));
      expect(
        (tester.getTopLeft(find.text('Connect your executor')) - beforeHeading)
            .distance,
        lessThan(.01),
        reason:
            'Reparenting the exit viewport must preserve the painted frame.',
      );

      await tester.pump(const Duration(milliseconds: 55));
      await navigate(tester, _back, elapsed: const Duration(milliseconds: 35));
      await navigate(tester, _next, elapsed: const Duration(milliseconds: 60));
      controller.setReducedMotion(true);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(_outgoing), findsNothing);
      expect(find.text('Smoother starts'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rapid reversals replace stale pages and finish exactly once', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false);
    addTearDown(controller.dispose);
    var completions = 0;
    await mount(tester, controller, onComplete: () => completions++);

    for (final key in [_next, _next, _back, _back, _next, _next, _next]) {
      await navigate(tester, key, elapsed: const Duration(milliseconds: 45));
      expect(find.byKey(_outgoing).evaluate().length, lessThanOrEqualTo(1));
      expect(find.byKey(_incoming), findsOneWidget);
      expect(
        find.byKey(const ValueKey('onboarding-page-stage')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.text('Executor Quick Launch'), findsOneWidget);
    expect(find.text('Welcome to Orion'), findsNothing);
    expect(find.text('Connect your executor'), findsNothing);
    expect(find.text('Smoother starts'), findsNothing);
    expect(completions, 0);
    expect(find.byKey(_outgoing), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(completions, 0, reason: 'Motion must never advance the tutorial.');

    await tester.tap(find.byKey(_next));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_next));
    await tester.pumpAndSettle();
    expect(completions, 1);
    expect(controller.introCompleted, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'enabling reduced motion during a swap removes departing content',
    (tester) async {
      final controller = OrionController(persistChanges: false);
      addTearDown(controller.dispose);
      await mount(tester, controller);
      await navigate(tester, _next);
      expect(find.byKey(_outgoing), findsOneWidget);

      controller.setReducedMotion(true);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_outgoing), findsNothing);
      expect(find.text('Welcome to Orion'), findsNothing);
      expect(find.text('Connect your executor'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);

      await tester.tap(find.byKey(_back));
      await tester.pump();
      expect(find.byKey(_outgoing), findsNothing);
      expect(find.text('Welcome to Orion'), findsOneWidget);
      expect(find.text('Connect your executor'), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final theme in [
    OrionThemePreferences.builtInPresets
        .singleWhere((preset) => preset.id == 'liquid-glass')
        .preferences,
    OrionThemePreferences(
      presetId: 'motion-test-custom',
      themeMode: ThemeMode.light,
      accent: const Color(0xFF34734B),
      gradientEnabled: true,
      gradientColors: const [Color(0xFFE6F4E9), Color(0xFFFFF7DE)],
      overrides: const {'ink': Color(0xFF192B1E)},
    ),
  ]) {
    for (final scale in [.8, 1.25]) {
      testWidgets(
        '${theme.presetId} transitions fit compact windows at GUI scale $scale',
        (tester) async {
          final controller = OrionController(persistChanges: false)
            ..setOrionTheme(theme);
          addTearDown(controller.dispose);
          await mount(
            tester,
            controller,
            size: const Size(680, 420),
            scale: scale,
          );
          final footer = tester.getRect(find.byKey(_next));
          expect(footer.top, greaterThanOrEqualTo(0));
          expect(footer.bottom, lessThanOrEqualTo(420));
          for (var page = 1; page < 4; page++) {
            await navigate(tester, _next);
            expect(find.byKey(_incoming), findsOneWidget);
            expect(tester.getRect(find.byKey(_next)).top, footer.top);
            expect(tester.takeException(), isNull);
            await tester.pump(const Duration(milliseconds: 180));
            expect(tester.takeException(), isNull);
            await tester.pumpAndSettle();
            expect(find.byKey(_outgoing), findsNothing);
            expect(tester.takeException(), isNull);
          }
          expect(tester.binding.transientCallbackCount, 0);
        },
      );
    }
  }
}
