import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/screens/intro_screen.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';

const _subtitle =
    'Orion is back, this time under the Google material 3 expressive design language.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('RobotoFlex')
      ..addFont(rootBundle.load('assets/fonts/RobotoFlex-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/RobotoFlex-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/RobotoFlex-Semibold.ttf'));
    await loader.load();
  });

  testWidgets('intro opens automatically at three seconds, exactly once', (
    tester,
  ) async {
    final controller = OrionController();
    addTearDown(controller.dispose);
    var completions = 0;
    await _mount(tester, controller, () => completions++);
    expect(find.text('Orion Expressive'), findsOneWidget);
    expect(find.text(_subtitle), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    await tester.pump(const Duration(milliseconds: 2999));
    expect(completions, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(completions, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(completions, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('showcase uses the exact title and holds the copy before exit', (
    tester,
  ) async {
    final controller = OrionController();
    addTearDown(controller.dispose);
    var completions = 0;
    await _mount(tester, controller, () => completions++, showcase: true);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Orion Expressive: Showcase'), findsOneWidget);
    expect(find.text(_subtitle), findsOneWidget);
    final introOpacities = tester.widgetList<Opacity>(
      find.descendant(
        of: find.byType(IntroScreen),
        matching: find.byType(Opacity),
      ),
    );
    expect(introOpacities.every((widget) => widget.opacity == 1), isTrue);
    await tester.pump(const Duration(milliseconds: 1250));
    final exiting = tester.widgetList<Opacity>(
      find.descendant(
        of: find.byType(IntroScreen),
        matching: find.byType(Opacity),
      ),
    );
    expect(exiting.first.opacity, lessThan(1));
    expect(exiting.first.opacity, greaterThan(0));
    expect(completions, 0);
    await tester.pump(const Duration(milliseconds: 150));
    expect(completions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final system in [false, true]) {
    testWidgets(
      '${system ? 'system' : 'preference'} reduced motion stays static for three seconds',
      (tester) async {
        final controller = OrionController();
        if (!system) controller.setReducedMotion(true);
        addTearDown(controller.dispose);
        var completions = 0;
        await _mount(
          tester,
          controller,
          () => completions++,
          systemReducedMotion: system,
        );
        expect(tester.binding.transientCallbackCount, 0);
        final opacities = tester.widgetList<Opacity>(
          find.descendant(
            of: find.byType(IntroScreen),
            matching: find.byType(Opacity),
          ),
        );
        expect(opacities.every((widget) => widget.opacity == 1), isTrue);
        await tester.pump(const Duration(milliseconds: 2999));
        expect(completions, 0);
        await tester.pump(const Duration(milliseconds: 1));
        expect(completions, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('disposing an intro cancels the automatic callback', (
    tester,
  ) async {
    final controller = OrionController();
    addTearDown(controller.dispose);
    var completions = 0;
    await _mount(tester, controller, () => completions++);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    expect(completions, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _mount(
  WidgetTester tester,
  OrionController controller,
  VoidCallback onComplete, {
  bool showcase = false,
  bool systemReducedMotion = false,
}) async {
  tester.view.physicalSize = const Size(860, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: orionTheme(Brightness.dark, controller.accentColor),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(860, 600),
          disableAnimations: systemReducedMotion,
        ),
        child: Scaffold(
          body: IntroScreen(
            controller: controller,
            onComplete: onComplete,
            showcase: showcase,
          ),
        ),
      ),
    ),
  );
}
