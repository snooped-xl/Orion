import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/models/synapse_studio_theme.dart';
import 'package:orion/services/synapse_theme_catalog.dart';
import 'package:orion/services/theme_studio_library.dart';
import 'package:orion/app.dart' show OrionStudioPreview;
import 'package:orion/screens/synapse_theme_studio.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/synapse_blue/synapse_blue_shell.dart';
import 'package:orion/synapse_og/synapse_og_shell.dart';
import 'package:orion/synapse_v3/synapse_v3_shell.dart';
import 'package:orion/synapse_x/synapse_x_shell.dart';
import 'package:orion/widgets/orion_overlay.dart';
import 'package:orion/widgets/synapse_studio_preview.dart';
import 'package:orion/widgets/synapse_theme_surface.dart';

class _StudioController extends OrionController {
  _StudioController() : super(persistChanges: false);
  bool failSave = false;
  bool reportSaveFailure = false;
  @override
  String? get persistenceError =>
      reportSaveFailure ? 'Disk unavailable' : super.persistenceError;
  @override
  Future<void> flushPersistence() async {
    if (failSave) throw const FileSystemException('Disk unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in <String, List<String>>{
      'RobotoFlex': [
        'assets/fonts/RobotoFlex-Regular.ttf',
        'assets/fonts/RobotoFlex-Medium.ttf',
        'assets/fonts/RobotoFlex-Semibold.ttf',
      ],
      'SynapseInter': [
        'assets/synapse_v3/fonts/Inter-Regular.ttf',
        'assets/synapse_v3/fonts/Inter-Medium.ttf',
        'assets/synapse_v3/fonts/Inter-Semibold.ttf',
        'assets/synapse_v3/fonts/Inter-Bold.ttf',
      ],
      'SynapseRubik': [
        'assets/synapse_v3/fonts/Rubik-Regular.ttf',
        'assets/synapse_v3/fonts/Rubik-Medium.ttf',
      ],
      'SynapseXUI': [
        'assets/synapse_x/fonts/Cantarell-Regular.otf',
        'assets/synapse_x/fonts/Cantarell-Bold.otf',
      ],
      'SynapseXMono': ['assets/synapse_x/fonts/LiberationMono-Regular.ttf'],
      'JetBrainsMono': ['assets/fonts/JetBrainsMono.ttf'],
    }.entries) {
      final loader = FontLoader(font.key);
      for (final asset in font.value) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
    if (const bool.fromEnvironment('STUDIO_SCREENSHOTS')) {
      final bytes = await File(
        '../../work/flutter-sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  late _StudioController c;
  late GlobalKey<SynapseThemeStudioScreenState> key;
  late int closed;
  setUp(() {
    c = _StudioController()..setReducedMotion(true);
    key = GlobalKey<SynapseThemeStudioScreenState>();
    closed = 0;
  });
  tearDown(() => c.dispose());

  Future<void> mount(
    WidgetTester tester, {
    InterfacePreset preset = InterfacePreset.synapseX,
    Size size = const Size(1180, 760),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('studio-capture'),
        child: MaterialApp(
          home: OrionOverlayTheme(
            controller: c,
            builder: (_) => SynapseThemeStudioScreen(
              key: key,
              controller: c,
              preset: preset,
              onClose: () => closed++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SynapseStudioTheme draft(WidgetTester tester) => tester
      .widget<SynapseStudioPreview>(find.byType(SynapseStudioPreview))
      .theme;

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('STUDIO_SCREENSHOTS')) return;
    final context = tester.element(find.byType(SynapseThemeStudioScreen));
    await tester.runAsync(() async {
      for (final widget in tester.widgetList<Image>(find.byType(Image))) {
        await precacheImage(widget.image, context);
      }
    });
    await tester.pump();
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('studio-capture')),
      );
      final image = await boundary.toImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '../../work/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  Future<void> panel(WidgetTester tester, String name) async {
    if (name == 'Layers') {
      await tester.tap(find.byKey(const ValueKey('studio-show-layers')));
    } else {
      await tester.tap(find.byKey(ValueKey('studio-mode:$name')));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('short editing panels keep the shared top edge', (tester) async {
    await mount(tester, preset: InterfacePreset.orion);
    final viewport = tester.getRect(
      find.byKey(const ValueKey('studio-content:Inspector')),
    );
    for (final mode in ['Easy theme', 'Images', 'Saved themes', 'Inspector']) {
      await panel(tester, mode);
      expect(
        tester.getRect(find.byKey(ValueKey('studio-content:$mode'))),
        viewport,
        reason: '$mode should fill the dock and align beneath its tabs',
      );
      expect(tester.takeException(), isNull);
    }
  });

  Future<void> editX(WidgetTester tester, double value) async {
    await tester.tap(find.byKey(const ValueKey('studio-layer:editor')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('studio-number:main:editor:X')),
      '$value',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'compact Layers drawer closes with Escape without closing Studio',
    (tester) async {
      await mount(tester, size: const Size(640, 448));
      await tester.tap(find.byKey(const ValueKey('studio-show-layers')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('studio-layer-search')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(closed, 0);
      expect(find.byKey(const ValueKey('studio-layer-search')), findsNothing);
      expect(find.byKey(const ValueKey('studio-apply')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'draft geometry, undo and redo leave live UI untouched until Apply',
    (tester) async {
      await mount(tester);
      expect(find.byType(SynapseXShell), findsOneWidget);
      expect(
        find.byKey(const ValueKey('studio-preview:editor')),
        findsOneWidget,
      );
      await editX(tester, 24);
      expect(draft(tester).window('main').elements['editor']!.x, 24);
      expect(
        c.getInterfacePreferences(InterfacePreset.synapseX)['themeStudio'],
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('studio-undo')));
      await tester.pumpAndSettle();
      expect(draft(tester).window('main').elements['editor']?.x ?? 0, 0);
      await tester.tap(find.byKey(const ValueKey('studio-redo')));
      await tester.pumpAndSettle();
      expect(draft(tester).window('main').elements['editor']!.x, 24);
      await tester.tap(find.byKey(const ValueKey('studio-apply')));
      await tester.pumpAndSettle();
      final saved = SynapseStudioTheme.fromJson(
        c.getInterfacePreferences(InterfacePreset.synapseX)['themeStudio'],
      );
      expect(saved.window('main').elements['editor']!.x, 24);
      expect(find.text('Applied to Synapse X'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('measured selection handles drag the actual preview element', (
    tester,
  ) async {
    await mount(tester);
    await capture(tester, 'studio-full');
    final handle = find.byKey(const ValueKey('studio-preview:editor'));
    await tester.drag(handle, const Offset(60, 30));
    await tester.pumpAndSettle();
    final moved = draft(tester).window('main').elements['editor'];
    expect(moved, isNotNull);
    expect(moved!.x, greaterThan(0));
    expect(
      c.getInterfacePreferences(InterfacePreset.synapseX)['themeStudio'],
      isNull,
    );
    expect(
      find.byKey(const ValueKey('studio-number:main:editor:X')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'selection outline follows resized translated translucent content',
    (tester) async {
      final custom = SynapseStudioTheme().withElement(
        'main',
        'editor',
        SynapseStudioElement(width: 80, height: 40, x: 12, y: 7, opacity: .4),
      );
      c.setInterfacePreference(
        InterfacePreset.synapseX,
        'themeStudio',
        custom.toJson(),
      );
      await mount(tester);
      final shell = tester.getRect(find.byType(SynapseXShell));
      final handle = tester.getRect(
        find.byKey(const ValueKey('studio-preview:editor')),
      );
      expect(handle.width / shell.width, closeTo(80 / 801, .003));
      expect(handle.height / shell.height, closeTo(40 / 355, .003));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'owner-close recovery never applies a draft and restores it later',
    (tester) async {
      await mount(tester);
      await editX(tester, 36);
      await key.currentState!.preserveDraft();
      expect(
        c.getInterfacePreferences(InterfacePreset.synapseX)['themeStudio'],
        isNull,
      );
      expect(
        c.getInterfacePreferences(InterfacePreset.synapseX)['themeStudioDraft'],
        isA<Map>(),
      );
      await tester.pumpWidget(const SizedBox());
      key = GlobalKey<SynapseThemeStudioScreenState>();
      await mount(tester);
      expect(find.text('Recovered unapplied draft'), findsOneWidget);
      expect(draft(tester).window('main').elements['editor']!.x, 36);
      await tester.tap(find.byKey(const ValueKey('studio-apply')));
      await tester.pumpAndSettle();
      expect(
        c.getInterfacePreferences(InterfacePreset.synapseX)['themeStudioDraft'],
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('unsaved close can keep editing or discard without committing', (
    tester,
  ) async {
    await mount(tester);
    await editX(tester, 18);
    await tester.tap(find.byKey(const ValueKey('studio-close')));
    await tester.pumpAndSettle();
    expect(find.text('Save your theme changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(closed, 0);
    expect(draft(tester).window('main').elements['editor']!.x, 18);
    await tester.tap(find.byKey(const ValueKey('studio-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(
      c.getInterfacePreferences(InterfacePreset.synapseX)['themeStudio'],
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'failed Apply keeps the draft and restores the previous live theme',
    (tester) async {
      await mount(tester);
      await editX(tester, 15);
      c.failSave = true;
      await tester.tap(find.byKey(const ValueKey('studio-apply')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not apply theme.'), findsOneWidget);
      expect(draft(tester).window('main').elements['editor']!.x, 15);
      expect(
        c.getInterfacePreferences(InterfacePreset.synapseX)['themeStudio'],
        isNull,
      );
      c.failSave = false;
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reported persistence failure cannot appear as a successful Apply',
    (tester) async {
      await mount(tester);
      await editX(tester, 29);
      c.reportSaveFailure = true;
      await tester.tap(find.byKey(const ValueKey('studio-apply')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Disk unavailable'), findsOneWidget);
      expect(
        c.getInterfacePreferences(InterfacePreset.synapseX)['themeStudio'],
        isNull,
      );
      expect(draft(tester).window('main').elements['editor']!.x, 29);
      c.reportSaveFailure = false;
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('import validates JSON and loads a local draft', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('studio-import')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('studio-import-json')),
      '{"wrong":true}',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('studio-import-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Expected a Theme Studio'), findsOneWidget);
    final imported = SynapseStudioTheme(
      name: 'Imported',
      colors: {'windowBg': 0xff213645},
    );
    await tester.enterText(
      find.byKey(const ValueKey('studio-import-json')),
      imported.encode(),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('studio-import-confirm')));
    await tester.pumpAndSettle();
    expect(draft(tester).name, 'Imported');
    expect(
      c.getInterfacePreferences(InterfacePreset.synapseX)['themeStudio'],
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'saved themes UI saves, loads, renames and deletes without applying',
    (tester) async {
      await mount(tester);
      await editX(tester, 24);
      await tester.tap(find.byKey(const ValueKey('studio-save-theme')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('studio-theme-name-input')),
        'My saved theme',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('studio-theme-name-confirm')));
      await tester.pumpAndSettle();
      final library = ThemeStudioLibrary(c, InterfacePreset.synapseX);
      final saved = library.themes.single;
      expect(saved.name, 'My saved theme');
      expect(
        c.getInterfacePreferences(InterfacePreset.synapseX)['themeStudio'],
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('studio-reset')));
      await tester.pumpAndSettle();
      await panel(tester, 'Saved themes');
      await tester.tap(find.byKey(ValueKey('studio-saved-load:${saved.id}')));
      await tester.pumpAndSettle();
      expect(draft(tester).window('main').elements['editor']!.x, 24);
      expect(
        c.getInterfacePreferences(InterfacePreset.synapseX)['themeStudio'],
        isNull,
      );
      await tester.tap(find.byKey(ValueKey('studio-saved-menu:${saved.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Export'), findsOneWidget);
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('studio-theme-name-input')),
        'Renamed theme',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('studio-theme-name-confirm')));
      await tester.pumpAndSettle();
      expect(library.themes.single.name, 'Renamed theme');
      await tester.tap(find.byKey(ValueKey('studio-saved-menu:${saved.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(library.themes, isEmpty);
      expect(find.text('No saved themes yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('saved theme controls fit the compact Studio panel', (
    tester,
  ) async {
    await ThemeStudioLibrary(c, InterfacePreset.orion).save(
      'A theme with a deliberately longer name',
      SynapseThemeCatalog.defaults(InterfacePreset.orion),
    );
    await mount(
      tester,
      preset: InterfacePreset.orion,
      size: const Size(640, 448),
    );
    await panel(tester, 'Saved themes');
    expect(
      find.text('A theme with a deliberately longer name'),
      findsOneWidget,
    );
    expect(find.text('Load'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Orion Execute selection edits the real production button', (
    tester,
  ) async {
    await mount(tester, preset: InterfacePreset.orion);
    final handle = find.byKey(const ValueKey('studio-preview:executeButton'));
    final before = tester.getRect(handle);
    await tester.enterText(
      find.byKey(const ValueKey('studio-layer-search')),
      'Execute',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-layer:executeButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('studio-number:main:executeButton:X')),
      '20',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final after = tester.getRect(handle);
    expect(after.left, greaterThan(before.left));
    expect(after.width, closeTo(before.width, .1));
    expect(draft(tester).window('main').elements['executeButton']!.x, 20);
    expect(
      c.getInterfacePreferences(InterfacePreset.orion)['themeStudio'],
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('studio-layer-search')),
      '',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await capture(tester, 'studio-orion-full');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('inspector inherited sizes use source GUI coordinates', (
    tester,
  ) async {
    c.setUiScale(1.25);
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('studio-layer:editor')));
    await tester.pumpAndSettle();
    final source = tester.getRect(find.byType(SynapseXShell));
    final editor = tester.getRect(
      find.byKey(const ValueKey('studio-preview:editor')),
    );
    final ratio = source.width / (801 / c.uiScale);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('studio-number:main:editor:Width')),
        matching: find.byType(TextField),
      ),
    );
    expect(
      double.parse(field.controller!.text),
      closeTo(editor.width / ratio, .1),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Orion import retains portable palette effects and element images as a draft',
    (tester) async {
      final original = c.orionTheme;
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFUlEQVR4nGOs2PLhPwMDAwMTAxQAAC9wAx8nztMDAAAAAElFTkSuQmCC';
      final image = SynapseStudioImage(data: 'data:image/png;base64,$png');
      final imported = SynapseThemeCatalog.defaults(InterfacePreset.orion)
          .copyWith(
            name: 'Portable Orion',
            orionTheme: OrionThemePreferences(
              gradientEnabled: true,
              rainEnabled: true,
              gradientColors: const [Color(0xff15333b), Color(0xff301533)],
            ),
          )
          .withElement(
            'main',
            'executeButton',
            SynapseStudioElement(x: 7, image: image),
          );
      await mount(tester, preset: InterfacePreset.orion);
      await tester.tap(find.byKey(const ValueKey('studio-import')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('studio-import-json')),
        imported.encode(),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('studio-import-confirm')));
      await tester.pumpAndSettle();
      expect(draft(tester).name, 'Portable Orion');
      expect(draft(tester).orionTheme, imported.orionTheme);
      expect(
        draft(tester).window('main').elements['executeButton']!.image!.data,
        image.data,
      );
      expect(c.orionTheme, original);
      expect(
        c.getInterfacePreferences(InterfacePreset.orion)['themeStudio'],
        isNull,
      );
      // Export uses the same document envelope as the saved library/import route.
      final portable = SynapseStudioTheme.decode(draft(tester).encode());
      expect(portable.orionTheme, imported.orionTheme);
      expect(portable.window('main').elements['executeButton']!.x, 7);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Orion palette, gradient and rain stay local until atomic Apply',
    (tester) async {
      final original = c.orionTheme;
      await mount(tester, preset: InterfacePreset.orion);
      expect(find.text('Theme Studio'), findsOneWidget);
      expect(find.byType(OrionStudioPreview), findsOneWidget);
      await panel(tester, 'Easy theme');
      final classic = find.byKey(
        const ValueKey('studio-orion-preset:original-orion'),
      );
      await tester.ensureVisible(classic);
      await tester.tap(classic);
      await tester.pumpAndSettle();
      expect(draft(tester).orionTheme!.basePalette, 'original-orion');
      expect(c.orionTheme, original);
      expect(
        c.getInterfacePreferences(InterfacePreset.orion)['themeStudio'],
        isNull,
      );
      final rain = find.byKey(const ValueKey('studio-orion-rain'));
      await tester.ensureVisible(rain);
      await tester.tap(rain);
      await tester.pumpAndSettle();
      expect(draft(tester).orionTheme!.rainEnabled, isTrue);
      expect(c.orionTheme, original);
      await tester.tap(find.byKey(const ValueKey('studio-apply')));
      await tester.pumpAndSettle();
      expect(c.orionTheme.basePalette, 'original-orion');
      expect(c.orionTheme.gradientEnabled, isTrue);
      expect(c.orionTheme.rainEnabled, isTrue);
      expect(
        c.getInterfacePreferences(InterfacePreset.orion)['themeStudio'],
        isA<Map>(),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Orion Apply failure restores the prior Theme Control palette', (
    tester,
  ) async {
    final original = OrionThemePreferences(
      gradientEnabled: true,
      gradientColors: const [Color(0xff132833), Color(0xff201629)],
    );
    c.setOrionTheme(original);
    await mount(tester, preset: InterfacePreset.orion);
    await panel(tester, 'Easy theme');
    await tester.ensureVisible(
      find.byKey(const ValueKey('studio-preset:ocean')),
    );
    await tester.tap(find.byKey(const ValueKey('studio-preset:ocean')));
    await tester.pumpAndSettle();
    c.reportSaveFailure = true;
    await tester.tap(find.byKey(const ValueKey('studio-apply')));
    await tester.pumpAndSettle();
    expect(c.orionTheme, original);
    expect(
      c.getInterfacePreferences(InterfacePreset.orion)['themeStudio'],
      isNull,
    );
    expect(find.textContaining('Disk unavailable'), findsOneWidget);
    c.reportSaveFailure = false;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Orion page previews preserve existing Theme Control and show actual panes',
    (tester) async {
      await mount(
        tester,
        preset: InterfacePreset.orion,
        size: const Size(640, 448),
      );
      for (final page in [
        'Script hub',
        'UI selection',
        'Theme Control',
        'Settings',
        'Editor',
      ]) {
        await tester.tap(find.byKey(const ValueKey('studio-orion-page')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(page).last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SynapseStudioPreview>(find.byType(SynapseStudioPreview))
              .previewPage,
          {
            'Script hub': 'scriptHub',
            'UI selection': 'uiSelection',
            'Theme Control': 'themeControl',
            'Settings': 'settings',
            'Editor': 'editor',
          }[page],
        );
        expect(tester.takeException(), isNull, reason: page);
      }
      expect(
        find.byKey(const ValueKey('studio-preview:editor')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final entry in <InterfacePreset, Type>{
    InterfacePreset.synapseV3: SynapseV3Shell,
    InterfacePreset.synapseBlue: SynapseBlueShell,
    InterfacePreset.synapseX: SynapseXShell,
    InterfacePreset.synapse2017: SynapseOgShell,
  }.entries) {
    testWidgets(
      '${entry.key.label} logo has real size, offset and opacity handles',
      (tester) async {
        c.setInterfacePreference(
          entry.key,
          'themeStudio',
          SynapseStudioTheme()
              .withElement(
                'main',
                'logo',
                SynapseStudioElement(width: 12, height: 10, opacity: .35),
              )
              .toJson(),
        );
        await mount(tester, preset: entry.key);
        final source = find.byType(entry.value);
        final frame = tester.getRect(source);
        final handle = find.byKey(const ValueKey('studio-preview:logo'));
        final before = tester.getRect(handle);
        final scale =
            frame.width /
            SynapseThemeCatalog.windows(entry.key).first.defaultSize.width;
        expect(before.width, closeTo(12 * scale, .02));
        expect(before.height, closeTo(10 * scale, .02));
        expect(
          find.descendant(
            of: find.byType(SynapseThemeLogo),
            matching: find.byWidgetPredicate(
              (w) => w is Opacity && w.opacity == .35,
            ),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('studio-layer:logo')));
        await tester.pumpAndSettle();
        for (final field in [('X', 11), ('Y', 5)]) {
          await tester.enterText(
            find.byKey(ValueKey('studio-number:main:logo:${field.$1}')),
            '${field.$2}',
          );
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
        }
        final after = tester.getRect(handle);
        expect(after.left - before.left, closeTo(11 * scale, .02));
        expect(after.top - before.top, closeTo(5 * scale, .02));
        expect(draft(tester).window('main').elements['logo']!.opacity, .35);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('${entry.key.label} uses actual shell and works at640×448', (
      tester,
    ) async {
      await mount(tester, preset: entry.key, size: const Size(640, 448));
      if (entry.key == InterfacePreset.synapseX) {
        await capture(tester, 'studio-compact');
      }
      expect(find.byType(entry.value), findsOneWidget);
      expect(
        find.byKey(const ValueKey('studio-apply')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('studio-preview:editor')),
        findsOneWidget,
      );
      await panel(tester, 'Easy theme');
      await tester.ensureVisible(
        find.byKey(const ValueKey('studio-preset:ocean')),
      );
      await tester.tap(find.byKey(const ValueKey('studio-preset:ocean')));
      await tester.pumpAndSettle();
      expect(draft(tester).name, 'Ocean');
      expect(c.getInterfacePreferences(entry.key)['themeStudio'], isNull);
      await panel(tester, 'Layers');
      await tester.enterText(
        find.byKey(const ValueKey('studio-layer-search')),
        'Code editor',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('studio-layer:editor')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio-layer:logo')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('${entry.key.label} previews every supported window', (
      tester,
    ) async {
      await mount(tester, preset: entry.key);
      for (final window in SynapseThemeCatalog.windows(entry.key).skip(1)) {
        await tester.tap(find.byKey(const ValueKey('studio-window')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(window.label).last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SynapseStudioPreview>(find.byType(SynapseStudioPreview))
              .window
              .id,
          window.id,
        );
        if (!window.hasOwnWindow) {
          expect(find.text('Shares the main window size.'), findsOneWidget);
          expect(
            find.byKey(ValueKey('studio-number:${window.id}:window:Width')),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull, reason: window.id);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
