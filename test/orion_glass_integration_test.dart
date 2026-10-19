import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:orion/app.dart';
import 'package:orion/bridge_notification_app.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/orion_glass.dart';
import 'package:orion/widgets/orion_overlay.dart';
import 'package:orion/widgets/native_rain_viewport.dart';

class _Controller extends OrionController {
  _Controller() : super(persistChanges: false);
  @override
  Future<void> searchRemoteScripts([String? query]) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final glass = OrionThemePreferences.builtInPresets
      .firstWhere((preset) => preset.id == 'liquid-glass')
      .preferences;
  setUpAll(() async {
    await OrionGlassScene.preload();
    for (final font in const [
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Regular.ttf'),
      ('JetBrainsMono', 'assets/fonts/JetBrainsMono.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  testWidgets('glass pages retain editing and reset completely to Expressive', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = _Controller()
      ..setReducedMotion(true)
      ..completeIntro()
      ..setOrionTheme(glass);
    addTearDown(c.dispose);
    await tester.pumpWidget(OrionApp(controller: c, nativeWindow: false));
    await tester.pumpAndSettle();
    final window = tester.widget<NativeRainViewport>(
      find.byType(NativeRainViewport),
    );
    expect(window.windowOpacity, .63);
    expect(window.rainEnabled, false);
    final glassScene = tester.widget<OrionGlassScene>(
      find.byType(OrionGlassScene).first,
    );
    expect(glassScene.enabled, isTrue);
    expect(glassScene.backdrop.runtimeType, OrionGlassBackdrop);
    expect(find.byType(LiquidGlassLens), findsWidgets);
    expect(
      tester
          .widgetList<LiquidGlassLens>(find.byType(LiquidGlassLens))
          .every((lens) => lens.honorBackdropAlpha),
      isTrue,
    );
    final mainSheet = tester.widget<OrionGlassSurface>(
      find.byType(OrionGlassSurface).first,
    );
    expect(mainSheet.showRim, isFalse);
    const code = 'local message = "glass"\nprint(message)';
    await tester.enterText(find.byKey(const ValueKey('code-editor')), code);
    await tester.pumpAndSettle();
    for (final page in [
      'Scripts',
      'UI Selection',
      'Theme Control',
      'Settings',
      'Editor',
    ]) {
      await tester.tap(find.byTooltip(page));
      await tester.pumpAndSettle();
      expect(
        OrionColors.of(tester.element(find.byType(OrionShell))).glassEnabled,
        isTrue,
      );
      expect(find.byType(OrionGlassSurface), findsWidgets);
      expect(
        tester
            .widgetList<OrionGlassSurface>(find.byType(OrionGlassSurface))
            .where(
              (surface) =>
                  surface.key is ValueKey<String> &&
                  (surface.key! as ValueKey<String>).value.startsWith(
                    'workspace-glass-',
                  ),
            )
            .every((surface) => !surface.edgeRefraction && !surface.showRim),
        isTrue,
        reason: 'Nested workspace glass must not add another heavy outline.',
      );
      expect(tester.takeException(), isNull, reason: page);
    }
    expect(c.activeDocument.content, code);
    c.setOrionTheme(
      glass.copyWith(
        gradientEnabled: true,
        gradientColors: const [Color(0xff163f38), Color(0xff24294d)],
        gradientStops: const [0, 1],
        gradientAngle: 90,
      ),
    );
    await tester.pumpAndSettle();
    final colors = OrionColors.of(tester.element(find.byType(OrionShell)));
    var backdrop = tester.widget<OrionGlassBackdrop>(
      find.byType(OrionGlassBackdrop).first,
    );
    expect(backdrop.useAuthoredBackground, true);
    expect(backdrop.authoredGradient, colors.backgroundGradient);
    expect(backdrop.authoredGradient!.begin, isNot(Alignment.topLeft));
    expect(backdrop.backdropOpacity, c.orionTheme.windowOpacity);
    c.setOrionTheme(c.orionTheme.copyWith(gradientEnabled: false));
    await tester.pumpAndSettle();
    backdrop = tester.widget<OrionGlassBackdrop>(
      find.byType(OrionGlassBackdrop).first,
    );
    expect(backdrop.useAuthoredBackground, true);
    expect(backdrop.authoredGradient, isNull);
    c.resetOrionTheme();
    await tester.pumpAndSettle();
    expect(
      OrionColors.of(tester.element(find.byType(OrionShell))).glassEnabled,
      isFalse,
    );
    expect(c.activeDocument.content, code);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('glass overlay sizes naturally and keeps its button functional', (
    tester,
  ) async {
    final c = _Controller()
      ..setReducedMotion(true)
      ..setOrionTheme(glass);
    addTearDown(c.dispose);
    var clicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OrionOverlayTheme(
              controller: c,
              builder: (context) => OrionOverlaySurface(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Glass menu'),
                    TextButton(
                      onPressed: () => clicks++,
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(clicks, 1);
    expect(
      tester.getSize(find.byType(OrionOverlaySurface)).height,
      lessThan(200),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'glass notification keeps identity and dismissal in its own scene',
    (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: orionTheme(
            Brightness.dark,
            glass.accent,
            preferences: glass,
            reducedMotion: true,
          ),
          home: Center(
            child: SizedBox(
              width: 396,
              height: 128,
              child: BridgeConnectionToast(
                username: 'Glass Preview',
                executorName: 'madium',
                reducedMotion: true,
                duration: const Duration(seconds: 10),
                onDismiss: () => dismissed = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Orion Bridge'), findsOneWidget);
      expect(find.text('Glass Preview'), findsOneWidget);
      expect(find.byType(OrionGlassScene), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      expect(dismissed, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
