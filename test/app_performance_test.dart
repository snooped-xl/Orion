import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/screens/settings_screen.dart';
import 'package:orion/screens/theme_control_screen.dart';
import 'package:orion/screens/ui_selection_screen.dart';
import 'package:orion/services/synapse_theme_catalog.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_density.dart';
import 'package:orion/theme/orion_theme.dart';

const _editor = ValueKey('code-editor');
const _capture = ValueKey('app-performance-capture');
const _captureRoot = String.fromEnvironment('ORION_PERF_CAPTURE_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in const [
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Regular.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Medium.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Semibold.ttf'),
      ('JetBrainsMono', 'assets/fonts/JetBrainsMono.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  Future<OrionController> mount(
    WidgetTester tester, {
    OrionThemePreferences? preferences,
  }) async {
    tester.view.physicalSize = const Size(822, 523);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = Directory.systemTemp.createTempSync('orion-perf-app-');
    final c =
        OrionController(storageDirectory: directory, persistChanges: false)
          ..setReducedMotion(true)
          ..completeIntro();
    await tester.runAsync(c.initialize);
    c.renameDocument(c.activeDocumentId, 'untitled.lua');
    c.updateDocumentContent(c.activeDocumentId, 'print("welcome back")');
    if (preferences != null) c.setOrionTheme(preferences);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _capture,
        child: OrionApp(key: UniqueKey(), controller: c, nativeWindow: false),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        c.dispose();
        await directory.delete(recursive: true);
      });
    });
    return c;
  }

  MaterialApp app(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp));
  TextField field(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(_editor));
  ThemeData editorTheme(WidgetTester tester) =>
      Theme.of(tester.element(find.byKey(_editor)));

  testWidgets(
    'editing preserves app theme identity and refreshes editor state',
    (tester) async {
      final c = await mount(tester);
      final before = app(tester);
      final theme = editorTheme(tester);
      final appElement = tester.element(find.byType(MaterialApp));
      final shellElement = tester.element(find.byType(OrionShell));
      var appBuilds = 0, shellBuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (element == appElement) appBuilds++;
        if (element == shellElement) shellBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      for (var index = 0; index < 30; index++) {
        c.updateDocumentContent(
          c.activeDocumentId,
          'print($index)\n-- line two',
        );
        await tester.pump();
      }
      expect(identical(app(tester).theme, before.theme), isTrue);
      expect(identical(app(tester).darkTheme, before.darkTheme), isTrue);
      expect(
        editorTheme(tester).extension<OrionColors>()!.accent,
        theme.extension<OrionColors>()!.accent,
      );
      expect(
        editorTheme(tester).extension<OrionColors>()!.background,
        theme.extension<OrionColors>()!.background,
      );
      expect(appBuilds, 0);
      expect(shellBuilds, 0);
      expect(field(tester).controller!.text, 'print(29)\n-- line two');
      expect(find.text('2 lines'), findsOneWidget);
      c.setEditorFontSize(18);
      await tester.pumpAndSettle();
      expect(field(tester).style!.fontSize, 18);
      expect(identical(app(tester).darkTheme, before.darkTheme), isTrue);
      debugOnRebuildDirtyWidget = previous;
    },
  );

  testWidgets('theme, Studio font and density changes remain live', (
    tester,
  ) async {
    final c = await mount(tester);
    final original = app(tester).darkTheme;
    c.setOrionTheme(c.orionTheme.copyWith(accent: const Color(0xffd3a4ff)));
    await tester.pumpAndSettle();
    expect(identical(app(tester).darkTheme, original), isFalse);
    expect(
      editorTheme(tester).extension<OrionColors>()!.accent,
      const Color(0xffd3a4ff),
    );
    c.setOrionCompactMode(true);
    await tester.pumpAndSettle();
    expect(
      OrionDensity.of(tester.element(find.byKey(_editor))).isCompact,
      isTrue,
    );
    final document = SynapseThemeCatalog.current(
      c,
      InterfacePreset.orion,
    ).copyWith(fontFamily: 'SynapseInter');
    c.applyThemeStudioState(InterfacePreset.orion, document: document.toJson());
    await tester.pumpAndSettle();
    expect(
      editorTheme(tester).textTheme.bodyMedium!.fontFamily,
      'SynapseInter',
    );
    c.setOrionTheme(c.orionTheme.copyWith(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();
    expect(editorTheme(tester).brightness, Brightness.light);
    expect(field(tester).controller!.text, 'print("welcome back")');
  });

  testWidgets(
    'hidden editor receives documents and settings before returning',
    (tester) async {
      final c = await mount(tester);
      final first = c.activeDocumentId;
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      c.updateDocumentContent(first, 'local count = 2\nprint(count)');
      final second = c.newDocument(
        name: 'background.lua',
        content: 'print("new")',
      );
      c.setEditorFontSize(17);
      c.setWordWrap(true);
      c.setShowLineNumbers(false);
      c.setOrionTheme(OrionThemePreferences.builtInPresets[1].preferences);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Editor'));
      await tester.pumpAndSettle();
      expect(field(tester).controller!.text, second.content);
      expect(field(tester).style!.fontSize, 17);
      expect(find.text('background.lua'), findsWidgets);
      c.selectDocument(first);
      await tester.pumpAndSettle();
      expect(field(tester).controller!.text, 'local count = 2\nprint(count)');
      expect(find.text('2 lines'), findsOneWidget);
      await tester.tap(find.byTooltip('UI Selection'));
      await tester.pumpAndSettle();
      expect(find.byType(UISelectionScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Theme Control'));
      await tester.pumpAndSettle();
      expect(find.byType(ThemeControlScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('theme-preset-expressive')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Editor'));
      await tester.pumpAndSettle();
      expect(field(tester).controller!.text, 'local count = 2\nprint(count)');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('app UI pixel capture fixture', (tester) async {
    for (final preset in OrionThemePreferences.builtInPresets.take(4)) {
      await mount(tester, preferences: preset.preferences);
      for (final (name, tooltip) in const [
        ('editor', 'Editor'),
        ('uis', 'UI Selection'),
        ('theme', 'Theme Control'),
        ('settings', 'Settings'),
      ]) {
        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(OrionShell));
        await tester.runAsync(() async {
          for (final image in tester.widgetList<Image>(find.byType(Image))) {
            await precacheImage(image.image, context);
          }
        });
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_capture),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File('$_captureRoot/${preset.id}-$name.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    }
  }, skip: _captureRoot.isEmpty);
}
