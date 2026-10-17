import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/interface_window_profile.dart';
import 'package:orion/state/orion_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final font in const [
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Regular.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Medium.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Semibold.ttf'),
      ('JetBrainsMono', 'assets/fonts/JetBrainsMono.ttf'),
      ('SynapseInter', 'assets/synapse_v3/fonts/Inter-Regular.ttf'),
      ('SynapseInter', 'assets/synapse_blue/fonts/Inter-Light.ttf'),
      ('SynapseInter', 'assets/synapse_blue/fonts/Inter-Black.ttf'),
      ('SynapseXMono', 'assets/synapse_x/fonts/LiberationMono-Regular.ttf'),
      ('OriginalNunito', 'assets/original_zenith/Fonts/nunito-wght.ttf'),
      ('OriginalAwpUI', 'assets/original_awp/Inter-Regular.ttf'),
      ('OriginalAwpUI', 'assets/original_awp/Inter-SemiBold.ttf'),
      ('OriginalXenoUI', 'assets/original_xeno/NotoSans-Regular.ttf'),
      ('OriginalXenoUI', 'assets/original_xeno/NotoSans-Black.ttf'),
      ('OriginalArial', 'assets/original_fonts/LiberationSans-Regular.ttf'),
      ('OriginalSans', 'assets/original_fonts/LiberationSans-Regular.ttf'),
      ('OriginalSegoeUI', 'assets/synapse_x/fonts/Cantarell-Regular.otf'),
      ('OriginalConsolas', 'assets/synapse_x/fonts/LiberationMono-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(font.$1)..addFont(rootBundle.load(font.$2));
      await loader.load();
    }
  });

  testWidgets('completed guide enters the editor without a continuous ticker', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(860, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = OrionController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      OrionApp(controller: controller, nativeWindow: false),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(controller.introCompleted, isFalse);
    for (var step = 0; step < 3; step++) {
      await tester.tap(find.byKey(const ValueKey('onboarding-next')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Open Orion'));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(controller.introCompleted, isTrue);
    expect(find.byTooltip('Editor'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [
    const Size(720, 480),
    const Size(822, 523),
    const Size(860, 600),
    const Size(1080, 720),
    const Size(1440, 940),
  ]) {
    testWidgets(
      'every interface preserves edits and fits ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = OrionController()
          ..setReducedMotion(true)
          ..completeIntro();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          OrionApp(controller: controller, nativeWindow: false),
        );
        await tester.pumpAndSettle();
        const source = '-- preserved across interfaces\nprint("Orion")';
        final editor = find.byKey(const ValueKey('code-editor'));
        await tester.enterText(editor, source);
        await tester.pumpAndSettle();
        for (final preset in InterfacePresetDetails.available) {
          final minimum = InterfaceWindowProfile.forInterface(
            controller,
            preset,
          ).minimumSize;
          tester.view.physicalSize = Size(
            size.width.clamp(minimum.width, double.infinity),
            size.height.clamp(minimum.height, double.infinity),
          );
          controller.setInterface(preset);
          if (preset.isStandalone) {
            await _openSourceEditor(tester, preset);
          } else {
            await tester.pumpAndSettle();
          }
          expect(
            controller.activeDocument.content,
            source,
            reason: preset.label,
          );
          expect(editor, findsOneWidget, reason: '${preset.label} editor');
          expect(
            tester.widget<TextField>(editor).controller!.text,
            source,
            reason: preset.label,
          );
          if (preset == InterfacePreset.synapseV3) {
            expect(
              find.byTooltip('Execute script · Ctrl Enter'),
              findsOneWidget,
            );
            expect(find.byTooltip('Execute file'), findsOneWidget);
            expect(find.text('Back to Orion'), findsNothing);
          } else if (const {
            InterfacePreset.synapseBlue,
            InterfacePreset.synapseX,
            InterfacePreset.synapse2017,
          }.contains(preset)) {
            expect(find.text('Back to Orion'), findsNothing);
            expect(find.text('Execute'), findsWidgets);
          } else if (preset == InterfacePreset.orion) {
            expect(find.text('Execute'), findsOneWidget);
            expect(find.text('Clients'), findsOneWidget);
          } else {
            expect(find.text('RC7'), findsNothing);
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '${preset.label} layout',
          );
        }
        // Reduced motion no longer delays teardown past the recovery debounce.
        await controller.flushPersistence();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final size in [
    const Size(720, 480),
    const Size(822, 523),
    const Size(860, 600),
    const Size(860, 640),
    const Size(1080, 720),
    const Size(1440, 940),
  ]) {
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      testWidgets(
        '${size.width.toInt()}x${size.height.toInt()} ${mode.name}: every screen fits',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = OrionController()
            ..setReducedMotion(true)
            ..setThemeMode(mode);
          addTearDown(controller.dispose);

          await tester.pumpWidget(
            OrionApp(controller: controller, nativeWindow: false),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Welcome layout');
          expect(find.text('Welcome to Orion'), findsOneWidget);
          for (var step = 0; step < 3; step++) {
            await tester.tap(find.byKey(const ValueKey('onboarding-next')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'Guide step $step');
          }
          await tester.tap(find.text('Open Orion'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Workspace layout');

          for (final destination in const [
            ('Scripts', Icons.folder_outlined),
            ('UI Selection', Icons.dashboard_customize_outlined),
            ('Theme Control', Icons.palette_outlined),
            ('Settings', Icons.tune_rounded),
          ]) {
            await tester.tap(find.byIcon(destination.$2).first);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$destination layout',
            );
          }

          if (size == const Size(1080, 720)) {
            final replay = find.text('Replay intro');
            expect(replay, findsOneWidget);
            final bottom = tester.getBottomRight(replay).dy;
            expect(bottom, lessThan(size.height));
          }

          // Clicking the preference caption uses the full row hit target.
          await tester.ensureVisible(find.text('Word wrap'));
          await tester.tap(find.text('Word wrap'));
          await tester.pumpAndSettle();
          expect(controller.wordWrap, isTrue);

          // The editor must still fit at its largest font preference.
          controller.setEditorFontSize(22);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Editor').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Large editor font');

          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Command palette layout',
          );
          expect(find.text('Search actions'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Closing command palette',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}

Future<void> _openSourceEditor(
  WidgetTester tester,
  InterfacePreset preset,
) async {
  if (preset == InterfacePreset.synapseV3) {
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }
  for (var frame = 0; frame < 110; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    final loginKey = switch (preset) {
      InterfacePreset.awp => 'awp-login',
      InterfacePreset.zenithV2 => 'zenith-login',
      InterfacePreset.calamari => 'calamari-login',
      _ => 'no-local-login',
    };
    final login = find.byKey(ValueKey(loginKey)).hitTestable();
    if (login.evaluate().isNotEmpty) {
      await tester.tap(login);
      await tester.pump(const Duration(milliseconds: 300));
      if (preset == InterfacePreset.zenithV2) {
        await tester.tap(find.byKey(const ValueKey('zenith-nav-1')));
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
    if (find
        .byKey(const ValueKey('code-editor'))
        .hitTestable()
        .evaluate()
        .isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
  }
  fail(
    '${preset.label} did not expose the editor after its local login/intro.',
  );
}
