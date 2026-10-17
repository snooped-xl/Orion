import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preferences.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/models/synapse_studio_theme.dart';
import 'package:orion/services/theme_studio_library.dart';
import 'package:orion/state/orion_controller.dart';

class _LibraryController extends OrionController {
  _LibraryController() : super(persistChanges: false);
  bool fail = false;
  @override
  String? get persistenceError => fail ? 'Disk unavailable' : null;
  @override
  Future<void> flushPersistence() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _LibraryController controller;
  setUp(() => controller = _LibraryController());
  tearDown(() => controller.dispose());

  for (final preset in [
    InterfacePreset.orion,
    InterfacePreset.synapseV3,
    InterfacePreset.synapseBlue,
    InterfacePreset.synapseX,
    InterfacePreset.synapse2017,
  ]) {
    test(
      '${preset.label} saves, loads, renames and deletes independently of Apply',
      () async {
        final library = ThemeStudioLibrary(controller, preset);
        final originalPalette = controller.orionTheme;
        final document = SynapseStudioTheme(
          name: 'Draft',
          colors: {'accent': 0xff9fc6ff},
          orionTheme: preset == InterfacePreset.orion
              ? OrionThemePreferences(
                  gradientEnabled: true,
                  rainEnabled: true,
                  gradientColors: const [Colors.red, Colors.blue],
                )
              : null,
        ).withElement('main', 'editor', SynapseStudioElement(x: 20, radius: 8));
        final saved = await library.save('My theme', document);
        expect(library.themes.single.name, 'My theme');
        expect(saved.theme.window('main').elements['editor']!.x, 20);
        expect(saved.theme.name, 'My theme');
        expect(
          controller.getInterfacePreferences(preset)['themeStudio'],
          isNull,
        );
        expect(controller.orionTheme, originalPalette);
        final renamed = await library.rename(saved.id, 'New name');
        expect(renamed.id, saved.id);
        expect(renamed.theme.name, 'New name');
        expect(renamed.theme.orionTheme, document.orionTheme);
        expect(
          SynapseStudioTheme.decode(
            renamed.document,
          ).window('main').elements['editor']!.radius,
          8,
        );
        await library.delete(saved.id);
        expect(library.themes, isEmpty);
      },
    );
  }

  test(
    'names reject empty and case-insensitive duplicates; updates retain IDs',
    () async {
      final library = ThemeStudioLibrary(controller, InterfacePreset.synapseX);
      final first = await library.save('Ocean', SynapseStudioTheme());
      await expectLater(
        library.save(' ocean ', SynapseStudioTheme()),
        throwsFormatException,
      );
      await expectLater(
        library.save('   ', SynapseStudioTheme()),
        throwsFormatException,
      );
      final updated = await library.save(
        'Ocean',
        SynapseStudioTheme(colors: {'text': 0xffeeeeee}),
        replaceId: first.id,
      );
      expect(updated.id, first.id);
      expect(library.themes, hasLength(1));
      expect(updated.theme.colors['text'], 0xffeeeeee);
    },
  );

  test('library has a bounded entry count', () async {
    final library = ThemeStudioLibrary(controller, InterfacePreset.synapseX);
    for (var i = 0; i < ThemeStudioLibrary.maximumThemes; i++) {
      await library.save('Theme $i', SynapseStudioTheme());
    }
    await expectLater(
      library.save('One too many', SynapseStudioTheme()),
      throwsFormatException,
    );
    expect(library.themes, hasLength(ThemeStudioLibrary.maximumThemes));
  });

  test('full nested image data survives preference copying and reload', () async {
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFUlEQVR4nGOs2PLhPwMDAwMTAxQAAC9wAx8nztMDAAAAAElFTkSuQmCC';
    final library = ThemeStudioLibrary(controller, InterfacePreset.synapseBlue);
    final document = SynapseStudioTheme().withElement(
      'main',
      'editor',
      SynapseStudioElement(
        image: SynapseStudioImage(data: 'data:image/png;base64,$png'),
      ),
    );
    await library.save('With image', document);
    final restored = readInterfacePreferences(
      controller.getInterfacePreferences(InterfacePreset.synapseBlue),
    );
    final source =
        ((restored[ThemeStudioLibrary.preferenceKey] as List).single
                as Map)['document']
            as String;
    expect(
      SynapseStudioTheme.decode(
        source,
      ).window('main').elements['editor']!.image!.data,
      'data:image/png;base64,$png',
    );
    expect(
      SynapseStudioTheme.decode(
        source,
      ).window('main').elements['editor']!.image!.bytes,
      isNotEmpty,
    );
  });

  test('failed save, rename and delete restore the previous library', () async {
    final library = ThemeStudioLibrary(controller, InterfacePreset.orion);
    final saved = await library.save('Keep me', SynapseStudioTheme());
    controller.fail = true;
    await expectLater(
      library.save('Fail', SynapseStudioTheme()),
      throwsFormatException,
    );
    await expectLater(
      library.rename(saved.id, 'Fail rename'),
      throwsFormatException,
    );
    await expectLater(library.delete(saved.id), throwsFormatException);
    expect(library.themes.single.name, 'Keep me');
    expect(
      controller.getInterfacePreferences(InterfacePreset.orion)['themeStudio'],
      isNull,
    );
  });
}
