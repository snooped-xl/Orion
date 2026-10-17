import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/models/synapse_studio_theme.dart';
import 'package:orion/screens/synapse_theme_studio.dart';
import 'package:orion/services/synapse_theme_catalog.dart';
import 'package:orion/services/theme_studio_library.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/widgets/orion_overlay.dart';
import 'package:orion/widgets/synapse_studio_preview.dart';

class _SaveController extends OrionController {
  _SaveController() : super(persistChanges: false);
  @override
  Future<void> flushPersistence() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'RobotoFlex': 'assets/fonts/RobotoFlex-Regular.ttf',
      'SynapseInter': 'assets/synapse_v3/fonts/Inter-Regular.ttf',
      'SynapseXUI': 'assets/synapse_x/fonts/Cantarell-Regular.otf',
      'SynapseXMono': 'assets/synapse_x/fonts/LiberationMono-Regular.ttf',
      'JetBrainsMono': 'assets/fonts/JetBrainsMono.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });
  late _SaveController controller;
  setUp(() => controller = _SaveController()..setReducedMotion(true));
  tearDown(() => controller.dispose());

  Future<void> mount(
    WidgetTester tester, {
    InterfacePreset preset = InterfacePreset.synapseX,
  }) async {
    tester.view.physicalSize = const Size(1180, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: OrionOverlayTheme(
          controller: controller,
          builder: (_) =>
              SynapseThemeStudioScreen(controller: controller, preset: preset),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mode(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(ValueKey('studio-mode:$name')));
    await tester.pumpAndSettle();
  }

  Future<void> load(WidgetTester tester, SavedStudioTheme saved) async {
    await mode(tester, 'Saved themes');
    await tester.tap(find.byKey(ValueKey('studio-saved-load:${saved.id}')));
    await tester.pumpAndSettle();
  }

  Future<void> nameAndConfirm(WidgetTester tester, String name) async {
    await tester.enterText(
      find.byKey(const ValueKey('studio-theme-name-input')),
      name,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('studio-theme-name-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'saving a loaded theme under another name creates a separate copy',
    (tester) async {
      final library = ThemeStudioLibrary(controller, InterfacePreset.synapseX);
      final original = await library.save(
        'Original saved theme',
        SynapseThemeCatalog.defaults(
          InterfacePreset.synapseX,
        ).withElement('main', 'editor', SynapseStudioElement(x: 17)),
      );
      await mount(tester);
      await load(tester, original);
      await tester.tap(find.byKey(const ValueKey('studio-save-theme')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(OrionAlertDialog),
          matching: find.text('Save a copy'),
        ),
        findsOneWidget,
      );
      await nameAndConfirm(tester, 'My new variation');
      expect(library.themes, hasLength(2));
      expect(library.themes.first.id, original.id);
      expect(library.themes.first.name, 'Original saved theme');
      expect(library.themes.last.name, 'My new variation');
      expect(library.themes.last.id, isNot(original.id));
      expect(
        library.themes.last.theme.window('main').elements['editor']!.x,
        17,
      );
      expect(
        controller.getInterfacePreferences(
          InterfacePreset.synapseX,
        )['themeStudio'],
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('explicit Update selected retains the loaded theme ID', (
    tester,
  ) async {
    final library = ThemeStudioLibrary(controller, InterfacePreset.synapseX);
    final original = await library.save(
      'Update me',
      SynapseThemeCatalog.defaults(InterfacePreset.synapseX),
    );
    await mount(tester);
    await load(tester, original);
    await mode(tester, 'Saved themes');
    await tester.tap(find.byKey(const ValueKey('studio-library-update')));
    await tester.pumpAndSettle();
    expect(find.text('Update theme'), findsOneWidget);
    await nameAndConfirm(tester, 'Explicitly updated');
    expect(library.themes, hasLength(1));
    expect(library.themes.single.id, original.id);
    expect(library.themes.single.name, 'Explicitly updated');
    expect(
      controller.getInterfacePreferences(
        InterfacePreset.synapseX,
      )['themeStudio'],
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('copy names stay unique within the saved name length limit', (
    tester,
  ) async {
    final library = ThemeStudioLibrary(controller, InterfacePreset.synapseX);
    final longName = List.filled(60, 'A').join();
    final original = await library.save(longName, SynapseStudioTheme());
    await library.save(
      '${longName.substring(0, 55)} copy',
      SynapseStudioTheme(),
    );
    await mount(tester);
    await load(tester, original);
    await tester.tap(find.byKey(const ValueKey('studio-save-theme')));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('studio-theme-name-input')),
    );
    expect(input.controller!.text.length, lessThanOrEqualTo(60));
    expect(input.controller!.text, endsWith(' copy 2'));
    await tester.tap(find.byKey(const ValueKey('studio-theme-name-confirm')));
    await tester.pumpAndSettle();
    expect(library.themes, hasLength(3));
    expect(library.themes.first.id, original.id);
    expect(library.themes.first.name, longName);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Easy accent edits retain the current Orion background', (
    tester,
  ) async {
    final original = OrionThemePreferences(
      overrides: const {'background': Color(0xff112233)},
    );
    controller.setOrionTheme(original);
    await mount(tester, preset: InterfacePreset.orion);
    await mode(tester, 'Easy theme');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('studio-easy-base')),
        matching: find.text('#112233'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('studio-easy-accent')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('theme-color-hex')),
      '#CC8866',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('theme-color-apply')));
    await tester.pumpAndSettle();
    final draft = tester
        .widget<SynapseStudioPreview>(find.byType(SynapseStudioPreview))
        .theme;
    final palette = SynapseThemeCatalog.orionPreferencesForTheme(draft);
    expect(palette.overrides['background'], const Color(0xff112233));
    expect(palette.accent, const Color(0xffcc8866));
    expect(controller.orionTheme, original);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
