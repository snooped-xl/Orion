import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/models/synapse_studio_theme.dart';
import 'package:orion/screens/theme_control_screen.dart';
import 'package:orion/services/synapse_theme_catalog.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/orion_studio_layer.dart';
import 'package:orion/widgets/orion_glass.dart';

OrionThemePreferences get glass => OrionThemePreferences.builtInPresets
    .singleWhere((preset) => preset.id == 'liquid-glass')
    .preferences;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Glassy uses a lighter neutral tint while keeping its effect independent',
    () {
      expect(
        OrionThemePreferences.builtInPresets
            .take(OrionThemePreferences.primaryPresetCount)
            .map((preset) => preset.id),
        [
          'expressive',
          'original-orion',
          'material-rain',
          'liquid-glass',
          'blue-glass',
        ],
      );
      expect(glass.basePalette, 'liquid-glass');
      expect(glass.liquidGlassEnabled, true);
      expect(glass.rainEnabled, false);
      expect(glass.windowOpacity, .63);
      expect(
        glass.windowOpacity,
        lessThan(
          OrionThemePreferences.builtInPresets
              .singleWhere((preset) => preset.id == 'material-rain')
              .preferences
              .windowOpacity,
        ),
      );
      expect(glass.gradientEnabled, false);
      expect(OrionThemePreferences.builtInPresets[3].name, 'Glassy');
      for (final preset in OrionThemePreferences.builtInPresets.where(
        (preset) => !{'liquid-glass', 'blue-glass'}.contains(preset.id),
      )) {
        expect(preset.preferences.liquidGlassEnabled, false, reason: preset.id);
      }
      expect(OrionThemePreferences.defaults.liquidGlassEnabled, false);
    },
  );

  test('only exact previous Glassy opacities upgrade', () {
    for (final opacity in const [.55, .70]) {
      final previous = glass.copyWith(windowOpacity: opacity);
      expect(OrionThemePreferences.fromJson(previous.toJson()), glass);
      for (final custom in [
        previous.copyWith(presetId: 'custom'),
        previous.copyWith(windowOpacity: .65),
        previous.copyWith(themeMode: ThemeMode.light),
        previous.copyWith(accent: const Color(0xffaa66cc)),
        previous.copyWith(overrides: {'editor': const Color(0xff222222)}),
      ]) {
        expect(OrionThemePreferences.fromJson(custom.toJson()), custom);
      }
    }
  });

  test('only exact shipped Glass builtins upgrade to the new preset', () {
    final first = <String, Object?>{
      'version': 2,
      'presetId': 'liquid-glass',
      'basePalette': 'liquid-glass',
      'themeMode': 'dark',
      'accent': 0xFFAFDFFF,
      'gradientEnabled': true,
      'rainEnabled': false,
      'liquidGlassEnabled': true,
      'windowOpacity': 1.0,
      'gradientColors': [0xFF111923, 0xFF3E596C, 0xFF17252F],
      'gradientStops': [0.0, .52, 1.0],
      'gradientAngle': 135.0,
      'surfaceTint': 0.0,
      'outlineStrength': 1.0,
      'overrides': <String, int>{},
    };
    final second = {
      ...first,
      'accent': 0xFFA1D7FF,
      'windowOpacity': .9,
      'outlineStrength': .65,
      'gradientColors': [0xFF181B20, 0xFF333B44, 0xFF181C22],
    };
    final third = {
      ...second,
      'accent': 0xFF62B0FF,
      'gradientColors': [0xFF0B1017, 0xFF142333, 0xFF0A1018],
    };
    for (final legacy in [first, second, third]) {
      expect(OrionThemePreferences.fromJson(legacy), glass);
      for (final patch in <Map<String, Object?>>[
        {'presetId': 'custom'},
        {'themeMode': 'light'},
        {'accent': 0xFF88B5FF},
        {'gradientEnabled': false},
        {'rainEnabled': true},
        {'liquidGlassEnabled': false},
        {'windowOpacity': .8},
        {
          'gradientColors': [0xFF111923, 0xFF3E596C, 0xFF17252E],
        },
        {
          'gradientStops': [0.0, .5, 1.0],
        },
        {'gradientAngle': 45.0},
        {'surfaceTint': .2},
        {'outlineStrength': .8},
        {
          'overrides': {'panel': 0xFF223344},
        },
      ]) {
        final edited = {...legacy, ...patch};
        expect(
          OrionThemePreferences.fromJson(edited).toJson(),
          edited,
          reason: 'A manual edit must remain exact: $patch',
        );
      }
    }
  });

  test(
    'Glass round trips JSON, native codec, and advanced theme documents',
    () {
      final edited = glass.copyWith(
        presetId: 'custom',
        accent: Colors.tealAccent,
        rainEnabled: true,
        windowOpacity: .92,
        overrides: const {'panel': Color(0xFF283C45)},
      );
      const codec = StandardMessageCodec();
      final decoded = OrionThemePreferences.fromJson(
        codec.decodeMessage(codec.encodeMessage(edited.toJson())),
      );
      expect(decoded, edited);
      expect(decoded.hashCode, edited.hashCode);
      expect(decoded.copyWith(liquidGlassEnabled: false), isNot(decoded));
      expect(
        OrionThemePreferences.fromJson(jsonDecode(jsonEncode(edited.toJson()))),
        edited,
      );
      final document = SynapseStudioTheme(orionTheme: edited);
      expect(SynapseStudioTheme.decode(document.encode()).orionTheme, edited);
      expect(
        OrionThemePreferences.fromJson({
          'liquidGlassEnabled': 'true',
        }).liquidGlassEnabled,
        false,
      );
      final legacy = Map<String, Object?>.from(edited.toJson())
        ..remove('liquidGlassEnabled');
      expect(OrionThemePreferences.fromJson(legacy).liquidGlassEnabled, false);
    },
  );

  test(
    'Easy and manual palette edits preserve Glass and Rain independently',
    () {
      final edited = glass.copyWith(rainEnabled: true);
      final easy = SynapseThemeCatalog.easy(
        InterfacePreset.orion,
        base: const Color(0xFF172D36).toARGB32(),
        accent: const Color(0xFFB9ECDE).toARGB32(),
        text: const Color(0xFFF0FAF8).toARGB32(),
        current: SynapseStudioTheme(orionTheme: edited),
      );
      expect(easy.orionTheme!.liquidGlassEnabled, true);
      expect(easy.orionTheme!.rainEnabled, true);
      expect(easy.orionTheme!.gradientColors, edited.gradientColors);
      final off = easy.orionTheme!.copyWith(liquidGlassEnabled: false);
      expect(off.rainEnabled, true);
      expect(off.basePalette, 'liquid-glass');
    },
  );

  test(
    'Glass saves, exports, restores, and resets through the real controller',
    () async {
      final storage = await Directory.systemTemp.createTemp('orion-glass-');
      addTearDown(() => storage.delete(recursive: true));
      final first = OrionController(storageDirectory: storage);
      await first.initialize();
      final custom = glass.copyWith(presetId: 'custom', surfaceTint: .3);
      first.setOrionTheme(custom);
      first.saveOrionTheme('Ice');
      final exported = first.exportOrionTheme();
      await first.flushPersistence();
      first.dispose();
      await first.flushPersistence();
      final restored = OrionController(storageDirectory: storage);
      addTearDown(() async {
        restored.dispose();
        await restored.flushPersistence();
      });
      await restored.initialize();
      expect(restored.orionTheme, custom);
      expect(restored.savedOrionThemes.single.preferences, custom);
      restored.resetOrionTheme();
      expect(restored.orionTheme.liquidGlassEnabled, false);
      expect(restored.importOrionTheme(exported), true);
      expect(restored.orionTheme, custom);
      final mirror = OrionController(persistChanges: false);
      addTearDown(mirror.dispose);
      mirror.applyWindowState(restored.exportWindowState());
      expect(mirror.orionTheme.liquidGlassEnabled, true);
      expect(mirror.orionTheme, custom);
      await restored.flushPersistence();
    },
  );

  for (final brightness in Brightness.values) {
    test('Glass ${brightness.name} has its own clear semantic palette', () {
      final colors = orionTheme(
        brightness,
        Colors.red,
        preferences: glass,
      ).extension<OrionColors>()!;
      expect(colors.glassEnabled, true);
      expect(colors.transparentSurfaces, true);
      expect(colors.chrome(colors.panel, role: 'panel'), Colors.transparent);
      expect(colors.stateFill(.08).a, closeTo(.08, .001));
      expect(colors.copyWith(panel: Colors.black).glassEnabled, true);
      final solid = orionTheme(
        brightness,
        Colors.red,
        preferences: glass.copyWith(liquidGlassEnabled: false),
      ).extension<OrionColors>()!;
      expect(solid.glassEnabled, false);
      expect(colors.lerp(solid, .25).glassEnabled, true);
      expect(colors.lerp(solid, .75).glassEnabled, false);
      final manual = orionTheme(
        brightness,
        Colors.red,
        preferences: glass.copyWith(overrides: const {'panel': Colors.black}),
      ).extension<OrionColors>()!;
      expect(manual.glassEnabled, true);
      expect(manual.chrome(manual.panel, role: 'panel'), Colors.black);
      expect(colors.ink.a, 1);
      expect(colors.muted.a, 1);
      expect((colors.background.r - colors.background.b).abs(), lessThan(.1));
      expect((colors.panel.r - colors.panel.b).abs(), lessThan(.1));
      if (brightness == Brightness.dark) {
        expect(colors.background.computeLuminance(), lessThan(.03));
        expect(colors.panel.computeLuminance(), lessThan(.03));
        expect(colors.ink.computeLuminance(), greaterThan(.8));
      }
    });
  }

  testWidgets('advanced paint overrides retain the Glass effect scope', (
    tester,
  ) async {
    final c = OrionController(persistChanges: false)..setOrionTheme(glass);
    addTearDown(c.dispose);
    c.setInterfacePreference(InterfacePreset.orion, 'themeStudio', {
      'windows': {
        'main': {
          'elements': {
            'execute': {'fill': 0xff2c4350, 'radius': 18},
          },
        },
      },
    });
    late OrionColors actual;
    await tester.pumpWidget(
      MaterialApp(
        theme: orionTheme(Brightness.dark, glass.accent, preferences: glass),
        home: OrionStudioLayer(
          controller: c,
          elementId: 'execute',
          child: Builder(
            builder: (context) {
              actual = OrionColors.of(context);
              return const SizedBox(width: 100, height: 40);
            },
          ),
        ),
      ),
    );
    expect(actual.glassEnabled, true);
    expect(actual.panel, const Color(0xff2c4350));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Glass buttons get real optical layers while existing themes do not',
    (tester) async {
      var pressed = 0;
      Future<void> mount(
        OrionThemePreferences preferences,
      ) => tester.pumpWidget(
        MaterialApp(
          theme: orionTheme(
            Brightness.dark,
            preferences.accent,
            preferences: preferences,
            reducedMotion: true,
          ),
          home: Scaffold(
            body: Row(
              children: [
                FilledButton(
                  onPressed: () => pressed++,
                  child: const Text('Run'),
                ),
                ElevatedButton(onPressed: () {}, child: const Text('Raised')),
                OutlinedButton(onPressed: () {}, child: const Text('Outline')),
                TextButton(onPressed: () {}, child: const Text('Text')),
                const FilledButton(onPressed: null, child: Text('Disabled')),
              ],
            ),
          ),
        ),
      );
      await mount(OrionThemePreferences.defaults);
      expect(find.byType(OrionGlassSurface), findsNothing);
      await mount(glass);
      await tester.pumpAndSettle();
      expect(find.byType(OrionGlassSurface), findsNWidgets(5));
      expect(
        tester
            .widgetList<OrionGlassSurface>(find.byType(OrionGlassSurface))
            .where((surface) => surface.interactive),
        hasLength(4),
      );
      final context = tester.element(find.text('Run'));
      final style = Theme.of(context).filledButtonTheme.style!;
      expect(style.backgroundColor!.resolve({}), Colors.transparent);
      expect(style.foregroundColor!.resolve({}), OrionColors.of(context).ink);
      expect(
        (style.shape!.resolve({})! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(20),
      );
      await tester.tap(find.text('Run'));
      expect(pressed, 1);
      expect(tester.takeException(), isNull);
      for (final preset in OrionThemePreferences.builtInPresets.take(3)) {
        await mount(preset.preferences);
        await tester.pumpAndSettle();
        expect(find.byType(OrionGlassSurface), findsNothing, reason: preset.id);
      }
    },
  );

  testWidgets('controls on glass use thin fills instead of stacked lenses', (
    tester,
  ) async {
    await tester.runAsync(OrionGlassScene.preload);
    var opacity = 1.0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        theme: orionTheme(
          Brightness.dark,
          glass.accent,
          preferences: glass,
          reducedMotion: true,
        ),
        home: SizedBox(
          width: 360,
          height: 180,
          child: StatefulBuilder(
            builder: (_, setState) {
              rebuild = setState;
              return OrionGlassScene(
                reducedMotion: true,
                backdrop: const ColoredBox(color: Color(0xff181b20)),
                child: OrionGlassSurface(
                  materialOpacity: opacity,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(onPressed: () {}, child: const Text('Run')),
                      OutlinedButton(
                        onPressed: () {},
                        child: const Text('Open'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OrionGlassSurface), findsOneWidget);
    final context = tester.element(find.text('Open'));
    expect(
      Theme.of(context).outlinedButtonTheme.style!.side!.resolve({}),
      BorderSide.none,
    );
    DecoratedBox fillOf(Type type, String label) => tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.widgetWithText(type, label),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is ShapeDecoration,
            ),
          )
          .first,
    );
    final primary = fillOf(FilledButton, 'Run').decoration as ShapeDecoration;
    final secondary =
        fillOf(OutlinedButton, 'Open').decoration as ShapeDecoration;
    expect(primary.color!.a, closeTo(.22, .001));
    expect(secondary.color!.a, 0);
    rebuild(() => opacity = 0);
    await tester.pumpAndSettle();
    expect(find.byType(OrionGlassSurface), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Theme Control groups stay quiet on the window glass sheet', (
    tester,
  ) async {
    await tester.runAsync(OrionGlassScene.preload);
    final c = OrionController(persistChanges: false)..setOrionTheme(glass);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: orionTheme(
          Brightness.dark,
          glass.accent,
          preferences: glass,
          reducedMotion: true,
        ),
        home: OrionGlassScene(
          reducedMotion: true,
          backdrop: const ColoredBox(color: Color(0xff0c1016)),
          child: OrionGlassSurface(
            child: Material(
              type: MaterialType.transparency,
              child: ThemeControlScreen(controller: c),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OrionGlassSurface), findsOneWidget);
    expect(find.text('Theme Control'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [const Size(680, 420), const Size(330, 560)]) {
    testWidgets(
      'Glass preset grid and effect controls work at ${size.width}px',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = OrionController(persistChanges: false)
          ..setReducedMotion(true);
        addTearDown(c.dispose);
        await tester.pumpWidget(
          AnimatedBuilder(
            animation: c,
            builder: (_, _) => MaterialApp(
              theme: orionTheme(
                Brightness.dark,
                c.orionTheme.accent,
                preferences: c.orionTheme,
                reducedMotion: true,
              ),
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ThemeControlScreen(controller: c),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final expressive = find.byKey(
          const ValueKey('theme-preset-expressive'),
        );
        final classic = find.byKey(
          const ValueKey('theme-preset-original-orion'),
        );
        final rain = find.byKey(const ValueKey('theme-preset-material-rain'));
        final glassCard = find.byKey(
          const ValueKey('theme-preset-liquid-glass'),
        );
        if (size.width > 340) {
          expect(
            tester.getTopLeft(expressive).dy,
            tester.getTopLeft(classic).dy,
          );
          expect(tester.getTopLeft(rain).dy, tester.getTopLeft(glassCard).dy);
        } else {
          expect(
            tester.getTopLeft(expressive).dx,
            tester.getTopLeft(classic).dx,
          );
          expect(
            tester.getTopLeft(classic).dy,
            greaterThan(tester.getTopLeft(expressive).dy),
          );
        }
        await tester.ensureVisible(glassCard);
        await tester.tap(glassCard);
        await tester.pumpAndSettle();
        expect(c.orionTheme.liquidGlassEnabled, true);
        expect(c.orionTheme.rainEnabled, false);
        tester
            .widget<Slider>(find.byKey(const ValueKey('theme-surface-tint')))
            .onChanged!(.25);
        await tester.pumpAndSettle();
        expect(c.orionTheme.liquidGlassEnabled, true);
        expect(c.orionTheme.presetId, 'custom');
        final layout = find.byKey(const ValueKey('theme-layout-controls'));
        await tester.ensureVisible(layout);
        await tester.tap(layout);
        await tester.pumpAndSettle();
        final toggle = find.descendant(
          of: layout,
          matching: find.text('Glassy'),
        );
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(c.orionTheme.liquidGlassEnabled, false);
        expect(c.orionTheme.basePalette, 'liquid-glass');
        expect(c.orionTheme.surfaceTint, .25);
        expect(tester.takeException(), isNull);
        final reset = find.byKey(const ValueKey('theme-reset'));
        await tester.ensureVisible(reset);
        await tester.tap(reset);
        await tester.pumpAndSettle();
        expect(c.orionTheme, OrionThemePreferences.defaults);
      },
    );
  }
}
