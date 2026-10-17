import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/models/synapse_studio_theme.dart';
import 'package:orion/services/synapse_theme_catalog.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/synapse_blue/blue_theme.dart';
import 'package:orion/synapse_og/og_theme.dart';
import 'package:orion/synapse_v3/synapse_v3_theme.dart';
import 'package:orion/synapse_x/synapse_x_theme.dart';
import 'package:orion/widgets/synapse_theme_surface.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFUlEQVR4nGOs2PLhPwMDAwMTAxQAAC9wAx8nztMDAAAAAElFTkSuQmCC';

void main() {
  SynapseStudioImage image({double opacity = 1, String fit = 'cover'}) =>
      SynapseStudioImage(data: _png, opacity: opacity, fit: fit);
  OrionController controller() {
    final result = OrionController(persistChanges: false);
    addTearDown(result.dispose);
    return result;
  }

  void commit(
    OrionController c,
    InterfacePreset preset,
    SynapseStudioTheme theme,
  ) => c.setInterfacePreference(preset, 'themeStudio', theme.toJson());

  test(
    'document normalizes finite geometry, bounded opacity and safe colour maps',
    () {
      final document = SynapseStudioTheme.fromJson({
        'name': '  Name\u0000\n ',
        'fontFamily': 'x;url(file:///secret)',
        'colors': {
          'editorBg': 0xff123456,
          'invalid': -1,
          'bad/key': 0xffffffff,
          'text': '#123456',
          'oversize': 0x1ffffffff,
        },
        'windows': {
          'main': {
            'width': -10,
            'height': 99999,
            'elements': {
              'editor': {
                'x': double.nan,
                'y': -99999,
                'width': 0,
                'height': double.infinity,
                'opacity': 9,
                'radius': -1,
                'fill': 0,
                'foreground': '#ffffff',
              },
            },
          },
          'unknown': {'width': 1000},
        },
      });
      expect(document.name, 'Name');
      expect(document.fontFamily, isNull);
      expect(document.colors, {'editorBg': 0xff123456, 'text': 0xff123456});
      expect(document.windows.keys, ['main']);
      final window = document.window('main');
      expect(window.width, 320);
      expect(window.height, 2160);
      final element = window.elements['editor']!;
      expect(element.x, 0);
      expect(element.y, -2160);
      expect(element.width, 8);
      expect(element.height, isNull);
      expect(element.opacity, 1);
      expect(element.radius, 0);
      expect(element.fill, 0);
      expect(element.foreground, 0xffffffff);
    },
  );

  test(
    'full JSON export/import roundtrips independent windows, layers and images',
    () {
      final document = SynapseStudioTheme(
        name: 'Portable',
        colors: {'buttonBg': 0xff123456},
        fontFamily: 'RobotoFlex',
        windows: {
          'main': SynapseStudioWindow(
            width: 900,
            height: 600,
            colors: {'buttonBg': 0xff334455},
            background: image(opacity: .3),
            overlay: image(opacity: .2, fit: 'contain'),
            logo: image(fit: 'contain'),
            elements: {
              'executeButton': SynapseStudioElement(
                x: 12,
                y: -3,
                width: 80,
                height: 32,
                opacity: .8,
                radius: 12,
                fill: 0xffabcdef,
                foreground: 0xff000000,
                border: 0xff123123,
                image: image(opacity: .1),
              ),
            },
          ),
          'settings': SynapseStudioWindow(
            width: 600,
            colors: {'text': 0xffeeeeee},
          ),
        },
      );
      final restored = SynapseStudioTheme.decode(document.encode());
      expect(restored.toJson(), document.toJson());
      expect(restored.window('main').background!.bytes, base64Decode(_png));
      expect(restored.window('settings').height, isNull);
      expect(restored.window('console').elements, isEmpty);
      expect(() => restored.colors.clear(), throwsUnsupportedError);
      expect(() => restored.windows.clear(), throwsUnsupportedError);
      expect(
        () => restored.window('main').elements.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'copy/reset operations preserve unrelated geometry, layers and explicit transparent fills',
    () {
      final original = SynapseStudioTheme(
        fontFamily: 'SynapseRubik',
        windows: {
          'main': SynapseStudioWindow(
            width: 900,
            height: 600,
            background: image(),
            overlay: image(),
            logo: image(),
            elements: {
              'editor': SynapseStudioElement(
                x: 20,
                width: 300,
                height: 200,
                radius: 8,
                fill: 0,
                foreground: 0xffeeeeee,
                border: 0xff888888,
                image: image(),
              ),
            },
          ),
        },
      );
      final edited = original.withElement(
        'main',
        'editor',
        original
            .window('main')
            .elements['editor']!
            .copyWith(clearForeground: true, clearImage: true),
      );
      expect(edited.window('main').elements['editor']!.fill, 0);
      expect(edited.window('main').elements['editor']!.foreground, isNull);
      expect(edited.window('main').elements['editor']!.image, isNull);
      expect(original.window('main').elements['editor']!.image, isNotNull);
      final reset = edited.withWindow(
        'main',
        edited
            .window('main')
            .copyWith(
              clearSize: true,
              clearBackground: true,
              clearOverlay: true,
              clearLogo: true,
            ),
      );
      expect(reset.window('main').width, isNull);
      expect(reset.window('main').height, isNull);
      expect(reset.window('main').background, isNull);
      expect(reset.window('main').elements['editor']!.x, 20);
      expect(reset.copyWith(clearFontFamily: true).fontFamily, isNull);
    },
  );

  test(
    'import rejects other formats, unsupported versions and malformed documents',
    () {
      for (final source in [
        '[]',
        '{}',
        '{broken',
        '{"format":"other","colors":{}}',
        '{"version":999,"colors":{}}',
      ]) {
        expect(() => SynapseStudioTheme.decode(source), throwsFormatException);
      }
      expect(SynapseStudioTheme.fromJson(null).windows, isEmpty);
      expect(
        SynapseStudioTheme.fromJson({'colors': 'bad', 'windows': 99}).colors,
        isEmpty,
      );
    },
  );

  test(
    'raster images normalize data URIs and reuse immutable decoded bytes during opacity edits',
    () {
      final original = image();
      expect(original.data, 'data:image/png;base64,$_png');
      expect(original.isValid, isTrue);
      final faded = original.copyWith(opacity: .25, fit: 'contain');
      expect(identical(original.bytes, faded.bytes), isTrue);
      expect(faded.opacity, .25);
      expect(faded.fit, 'contain');
      expect(() => faded.bytes![0] = 0, throwsUnsupportedError);
      expect(
        SynapseStudioImage(
          data: _png,
          opacity: double.nan,
          fit: 'unknown',
        ).opacity,
        1,
      );
      expect(SynapseStudioImage(data: _png, fit: 'unknown').fit, 'cover');
      expect(
        SynapseStudioImage(data: base64Encode([255, 216, 255, 217])).data,
        startsWith('data:image/jpeg;base64,'),
      );
      expect(
        SynapseStudioImage(
          data: base64Encode(ascii.encode('RIFF1234WEBP5678')),
        ).data,
        startsWith('data:image/webp;base64,'),
      );
    },
  );

  test(
    'image imports reject URLs, SVG, GIF, corrupt base64 and oversized payloads',
    () {
      for (final data in [
        'https://example.com/image.png',
        '/tmp/photo.png',
        'data:image/svg+xml;base64,PHN2Zy8+',
        'data:image/gif;base64,R0lGODlh',
        'data:image/png;base64,!invalid!',
        base64Encode(utf8.encode('not an image')),
      ]) {
        expect(SynapseStudioImage(data: data).isValid, isFalse, reason: data);
        expect(SynapseStudioImage.fromJson({'data': data}), isNull);
      }
      final huge = Uint8List(SynapseStudioImage.maximumBytes + 1)
        ..setRange(0, base64Decode(_png).length, base64Decode(_png));
      expect(SynapseStudioImage(data: base64Encode(huge)).isValid, isFalse);
      final giantPixels = base64Decode(_png);
      ByteData.sublistView(giantPixels).setUint32(16, 20000);
      expect(
        SynapseStudioImage(data: base64Encode(giantPixels)).isValid,
        isFalse,
      );
    },
  );

  test(
    'all four Original catalogues preserve the existing exact source roles',
    () {
      expect(SynapseThemeCatalog.supported.toSet(), {
        InterfacePreset.orion,
        InterfacePreset.synapseV3,
        InterfacePreset.synapseBlue,
        InterfacePreset.synapseX,
        InterfacePreset.synapse2017,
      });
      expect(
        SynapseThemeCatalog.defaults(InterfacePreset.synapseV3).colors,
        V3ThemePresets.colors['framework'],
      );
      expect(
        SynapseThemeCatalog.defaults(InterfacePreset.synapseBlue).colors,
        BluePalette.defaults,
      );
      expect(
        SynapseThemeCatalog.defaults(InterfacePreset.synapseX).colors,
        SynapseXTheme.defaults,
      );
      expect(SynapseThemeCatalog.defaults(InterfacePreset.synapse2017).colors, {
        for (final e in OgTheme.colors.entries)
          e.key: 0xff000000 | int.parse(e.value.substring(1), radix: 16),
      });
      for (final preset in SynapseThemeCatalog.supported) {
        expect(
          SynapseThemeCatalog.roles(preset).map((role) => role.key),
          SynapseThemeCatalog.defaults(preset).colors.keys,
        );
      }
    },
  );

  test(
    'legacy palette preferences migrate read-only until a Studio document is committed',
    () {
      final c = controller();
      c.updateSynapsePreferences(
        themePreset: 'ocean',
        themeColors: {'topBar.text': 0xff123456},
        uiFontFamily: 'SynapseRubik',
      );
      c.setInterfacePreference(InterfacePreset.synapseBlue, 'themeColors', {
        'shellBg': 0xff223344,
      });
      c.setInterfacePreference(
        InterfacePreset.synapseX,
        'theme.buttonBg',
        0xff334455,
      );
      c.setInterfacePreference(InterfacePreset.synapse2017, 'theme', {
        'windowBg': '#445566',
      });
      expect(
        SynapseThemeCatalog.current(
          c,
          InterfacePreset.synapseV3,
        ).colors['topBar.text'],
        0xff123456,
      );
      expect(
        SynapseThemeCatalog.current(c, InterfacePreset.synapseV3).fontFamily,
        'SynapseRubik',
      );
      expect(
        SynapseThemeCatalog.current(
          c,
          InterfacePreset.synapseBlue,
        ).colors['shellBg'],
        0xff223344,
      );
      expect(
        SynapseThemeCatalog.current(
          c,
          InterfacePreset.synapseX,
        ).colors['buttonBg'],
        0xff334455,
      );
      expect(
        SynapseThemeCatalog.current(
          c,
          InterfacePreset.synapse2017,
        ).colors['windowBg'],
        0xff445566,
      );
      for (final preset in SynapseThemeCatalog.supported) {
        expect(SynapseThemeCatalog.hasStudio(c, preset), isFalse);
        expect(
          identical(
            SynapseThemeCatalog.current(c, preset),
            SynapseThemeCatalog.current(c, preset),
          ),
          isTrue,
        );
      }
      commit(
        c,
        InterfacePreset.synapseX,
        SynapseThemeCatalog.defaults(
          InterfacePreset.synapseX,
        ).copyWith(colors: {'buttonBg': 0xff667788}),
      );
      expect(
        SynapseThemeCatalog.colors(
          c,
          InterfacePreset.synapseX,
          'main',
        )['buttonBg'],
        0xff667788,
      );
      c.setInterfacePreference(InterfacePreset.synapseX, 'themeStudio', null);
      expect(
        SynapseThemeCatalog.colors(
          c,
          InterfacePreset.synapseX,
          'main',
        )['buttonBg'],
        0xff334455,
      );
    },
  );

  test(
    'legacy OG image/logo and Blue wallpaper migrate into bounded portable layers',
    () async {
      final c = controller();
      c.setInterfacePreference(InterfacePreset.synapse2017, 'theme', {
        'overlayDataUrl': image().data,
        'overlayOpacity': .4,
        'overlayMode': 'top',
        'logoDataUrl': image().data,
      });
      final og = SynapseThemeCatalog.current(
        c,
        InterfacePreset.synapse2017,
      ).window('main');
      expect(og.overlay!.opacity, .4);
      expect(og.logo!.data, image().data);
      final temp = await Directory.systemTemp.createTemp('studio-wallpaper-');
      addTearDown(() => temp.delete(recursive: true));
      final file = await File(
        '${temp.path}/wallpaper.png',
      ).writeAsBytes(base64Decode(_png));
      c.setInterfacePreference(
        InterfacePreset.synapseBlue,
        'backgroundImagePath',
        file.path,
      );
      c.setInterfacePreference(
        InterfacePreset.synapseBlue,
        'backgroundOpacity',
        .6,
      );
      final blue = SynapseThemeCatalog.current(
        c,
        InterfacePreset.synapseBlue,
      ).window('main');
      expect(blue.background!.opacity, .6);
      expect(blue.background!.data, image().data);
    },
  );

  test(
    'global, per-window and structural element colours are effective and isolated',
    () {
      final c = controller();
      final doc = SynapseThemeCatalog.defaults(InterfacePreset.synapseV3)
          .copyWith(
            colors: {'topBar.bg': 0xff112233, 'topBar.text': 0xffeeeeee},
            windows: {
              'settings': SynapseStudioWindow(
                colors: {'topBar.bg': 0xff223344},
                elements: {
                  'titleBar': SynapseStudioElement(
                    fill: 0xff334455,
                    foreground: 0xffabcdef,
                  ),
                  'settingsControls': SynapseStudioElement(
                    fill: 0xff445566,
                    border: 0xff778899,
                  ),
                },
              ),
            },
          );
      commit(c, InterfacePreset.synapseV3, doc);
      final main = SynapseThemeCatalog.colors(
        c,
        InterfacePreset.synapseV3,
        'main',
      );
      final settings = SynapseThemeCatalog.colors(
        c,
        InterfacePreset.synapseV3,
        'settings',
      );
      expect(main['topBar.bg'], 0xff112233);
      expect(main['topBar.text'], 0xffeeeeee);
      expect(settings['topBar.bg'], 0xff334455);
      expect(settings['topBar.text'], 0xffabcdef);
      expect(settings['settingsChrome.controlBg'], 0xff445566);
      expect(settings['settingsChrome.controlBorder'], 0xff778899);
      expect(main['settingsChrome.controlBg'], isNot(0xff445566));
      expect(
        settings,
        SynapseThemeCatalog.colorsForTheme(
          doc,
          InterfacePreset.synapseV3,
          'settings',
        ),
      );
    },
  );

  test(
    'chosen backgrounds open opaque structural surfaces and preserve button colours',
    () {
      for (final preset in SynapseThemeCatalog.synapsePresets) {
        final c = controller();
        final doc = SynapseThemeCatalog.defaults(
          preset,
        ).withWindow('main', SynapseStudioWindow(background: image()));
        commit(c, preset, doc);
        final colors = SynapseThemeCatalog.colors(c, preset, 'main');
        final background = preset == InterfacePreset.synapseV3
            ? 'shell.windowBg'
            : preset == InterfacePreset.synapseBlue
            ? 'shellBg'
            : 'windowBg';
        final button = preset == InterfacePreset.synapseV3
            ? 'actionBar.buttonBg'
            : preset == InterfacePreset.synapseBlue
            ? 'editorControlBarButtonFrom'
            : 'buttonBg';
        expect((colors[background]! >> 24) & 255, 0);
        expect(colors[button], doc.colors[button]);
      }
    },
  );

  test(
    'Easy themes cover every role while preserving window geometry and images',
    () {
      for (final preset in SynapseThemeCatalog.synapsePresets) {
        final original = SynapseThemeCatalog.defaults(preset);
        final role = original.colors.keys.first;
        final custom = original.withWindow(
          'main',
          SynapseStudioWindow(
            width: 1000,
            height: 700,
            background: image(),
            colors: {role: 0xff123456},
            elements: {
              'editor': SynapseStudioElement(
                x: 12,
                width: 400,
                fill: 0xff334455,
                foreground: 0xffeeeeee,
                image: image(),
              ),
            },
          ),
        );
        final easy = SynapseThemeCatalog.easy(
          preset,
          current: custom,
          base: 0xff101a2a,
          accent: 0xff77aaff,
          text: 0xfff0f4ff,
        );
        expect(easy.colors.keys, original.colors.keys);
        expect(easy.window('main').colors[role], easy.colors[role]);
        expect(easy.window('main').width, 1000);
        expect(
          easy.window('main').background!.data,
          custom.window('main').background!.data,
        );
        expect(easy.window('main').elements['editor']!.x, 12);
        expect(easy.window('main').elements['editor']!.fill, 0xff101a2a);
        expect(easy.window('main').elements['editor']!.foreground, 0xfff0f4ff);
        expect(easy.window('main').elements['editor']!.image, isNotNull);
        for (final e in original.colors.entries) {
          expect(easy.colors[e.key]! >> 24, e.value >> 24);
        }
        expect(
          SynapseThemeCatalog.preset(preset, 'original').toJson(),
          original.toJson(),
        );
        expect(
          SynapseThemeCatalog.preset(preset, 'ocean').colors,
          isNot(original.colors),
        );
      }
    },
  );

  test(
    'catalogue exposes only real windows/layers with safe preview bounds',
    () {
      for (final preset in SynapseThemeCatalog.supported) {
        for (final window in SynapseThemeCatalog.windows(preset)) {
          final elements = SynapseThemeCatalog.elements(preset, window.id);
          expect(elements.map((e) => e.id).toSet().length, elements.length);
          for (final element in elements) {
            expect(element.bounds.left, greaterThanOrEqualTo(0));
            expect(element.bounds.top, greaterThanOrEqualTo(0));
            expect(
              element.bounds.right,
              lessThanOrEqualTo(window.defaultSize.width),
            );
            expect(
              element.bounds.bottom,
              lessThanOrEqualTo(window.defaultSize.height),
            );
            expect(element.bounds.width, greaterThan(0));
            expect(element.bounds.height, greaterThan(0));
          }
        }
      }
      final blueSettings = SynapseThemeCatalog.windows(
        InterfacePreset.synapseBlue,
      ).singleWhere((e) => e.id == 'settings');
      expect(blueSettings.hasOwnWindow, isFalse);
      expect(
        SynapseThemeCatalog.windows(
          InterfacePreset.synapseX,
        ).singleWhere((e) => e.id == 'settings').hasOwnWindow,
        isTrue,
      );
      expect(
        SynapseThemeCatalog.elements(
          InterfacePreset.synapseV3,
          'undockedEditor',
        ).any((e) => e.id == 'logo'),
        isFalse,
      );
      expect(
        SynapseThemeCatalog.elements(
          InterfacePreset.synapseV3,
          'console',
        ).map((e) => e.id),
        ['consoleOutput'],
      );
    },
  );

  test(
    'portable Orion documents preserve gradients, effects and legacy imports',
    () {
      final preferences = OrionThemePreferences(
        presetId: 'portable',
        basePalette: 'original-orion',
        accent: Colors.tealAccent,
        gradientEnabled: true,
        gradientColors: const [Colors.black, Colors.indigo],
        gradientStops: const [0, .7],
        gradientAngle: 42,
        rainEnabled: true,
        windowOpacity: .76,
        overrides: const {'editor': Color(0xff182020)},
      );
      final original = SynapseThemeCatalog.defaults(InterfacePreset.orion)
          .copyWith(orionTheme: preferences)
          .withWindow('main', SynapseStudioWindow(background: image()));
      final encoded = original.toJson();
      expect(encoded['format'], 'orion-theme-studio');
      final restored = SynapseStudioTheme.decode(original.encode());
      expect(restored.orionTheme!.toJson(), preferences.toJson());
      expect(restored.window('main').background!.data, image().data);
      expect(original.copyWith(name: 'Renamed').orionTheme, preferences);
      expect(original.copyWith(clearOrionTheme: true).orionTheme, isNull);
      expect(
        SynapseStudioTheme.decode(
          jsonEncode({...encoded, 'format': 'orion-synapse-studio'}),
        ).orionTheme!.toJson(),
        preferences.toJson(),
      );
      expect(
        SynapseStudioTheme.fromJson({'orionTheme': 'invalid'}).orionTheme,
        isNull,
      );
    },
  );

  test(
    'Orion exposes semantic roles, real major layers and proportional compact sizes',
    () {
      final theme = SynapseThemeCatalog.defaults(InterfacePreset.orion);
      expect(theme.fontFamily, 'RobotoFlex');
      expect(theme.colors.keys.toSet(), {
        ...OrionThemePreferences.colorRoles,
        'accent',
      });
      expect(theme.orionTheme, OrionThemePreferences.defaults);
      expect(
        SynapseThemeCatalog.windows(InterfacePreset.orion).map((w) => w.id),
        ['main'],
      );
      expect(
        SynapseThemeCatalog.windowSize(theme, InterfacePreset.orion, 'main'),
        const Size(822, 523),
      );
      expect(
        SynapseThemeCatalog.windowSize(
          theme,
          InterfacePreset.orion,
          'main',
          compactMode: true,
        ),
        const Size(740, 470),
      );
      final custom = theme.withWindow(
        'main',
        SynapseStudioWindow(width: 1000, height: 700),
      );
      expect(
        SynapseThemeCatalog.windowSize(
          custom,
          InterfacePreset.orion,
          'main',
          compactMode: true,
        ),
        const Size(900, 629),
      );
      final descriptors = SynapseThemeCatalog.elements(
        InterfacePreset.orion,
        'main',
      );
      expect(
        descriptors.map((e) => e.id),
        containsAll([
          'titleBar',
          'logo',
          'sidebar',
          'content',
          'workspace',
          'editor',
          'tabs',
          'actions',
          'executeButton',
          'clientsButton',
          'navTheme',
          'libraryContent',
          'uiSelection',
          'themeControls',
          'settingsControls',
        ]),
      );
      expect(descriptors.map((e) => e.id).toSet().length, descriptors.length);
      expect(
        SynapseThemeCatalog.synapsePresets,
        isNot(contains(InterfacePreset.orion)),
      );
    },
  );

  test(
    'existing Orion Theme Control remains authoritative after advanced Studio edits',
    () {
      final c = controller();
      final classic = OrionThemePreferences.builtInPresets
          .singleWhere((p) => p.id == 'original-orion')
          .preferences;
      c.setOrionTheme(classic);
      final initial = SynapseThemeCatalog.current(c, InterfacePreset.orion);
      expect(SynapseThemeCatalog.orionPreferencesForTheme(initial), classic);
      expect(initial.orionTheme!.overrides, isEmpty);
      final stored = initial
          .copyWith(colors: {'accent': 0xff00ff00})
          .withWindow(
            'main',
            SynapseStudioWindow(
              width: 950,
              colors: {'ink': 0xffff0000},
              background: image(),
              elements: {'logo': SynapseStudioElement(x: 12)},
            ),
          );
      commit(c, InterfacePreset.orion, stored);
      final updated = classic.copyWith(
        accent: Colors.blueAccent,
        overrides: const {'ink': Color(0xffffffdd)},
      );
      c.setOrionTheme(updated);
      final live = SynapseThemeCatalog.current(c, InterfacePreset.orion);
      expect(live.orionTheme, updated);
      expect(live.colors, SynapseThemeCatalog.orionPalette(updated));
      expect(live.window('main').colors, isEmpty);
      expect(live.window('main').width, 950);
      expect(live.window('main').background, isNotNull);
      expect(live.window('main').elements['logo']!.x, 12);
      expect(
        identical(live, SynapseThemeCatalog.current(c, InterfacePreset.orion)),
        isTrue,
      );
    },
  );

  test(
    'Orion materializes only edited roles and preserves the complete effect system',
    () {
      final preferences = OrionThemePreferences.builtInPresets
          .singleWhere((p) => p.id == 'material-rain')
          .preferences
          .copyWith(
            gradientEnabled: true,
            gradientColors: const [Color(0xff101020), Color(0xff202030)],
            gradientAngle: 77,
          );
      final initial = SynapseThemeCatalog.defaults(InterfacePreset.orion)
          .copyWith(
            orionTheme: preferences,
            colors: SynapseThemeCatalog.orionPalette(preferences),
          );
      final edited = initial
          .copyWith(
            colors: {
              ...initial.colors,
              'panel': 0xff183030,
              'accent': 0xff66cccc,
            },
          )
          .withWindow(
            'main',
            SynapseStudioWindow(colors: {'editor': 0xff081818}),
          );
      final applied = SynapseThemeCatalog.orionPreferencesForTheme(edited);
      expect(applied.presetId, 'custom');
      expect(applied.overrides, {
        'panel': const Color(0xff183030),
        'editor': const Color(0xff081818),
      });
      expect(applied.accent, const Color(0xff66cccc));
      expect(applied.basePalette, 'material-rain');
      expect(applied.rainEnabled, isTrue);
      expect(applied.windowOpacity, .9);
      expect(applied.gradientColors, preferences.gradientColors);
      expect(applied.gradientAngle, 77);
      final easy = SynapseThemeCatalog.easy(
        InterfacePreset.orion,
        base: 0xff111111,
        accent: 0xff77bbff,
        text: 0xffeeeeee,
        current: edited.withWindow(
          'main',
          edited
              .window('main')
              .copyWith(
                width: 1000,
                background: image(),
                elements: {'editor': SynapseStudioElement(x: 14)},
              ),
        ),
      );
      expect(easy.orionTheme!.rainEnabled, isTrue);
      expect(easy.orionTheme!.gradientAngle, 77);
      expect(easy.orionTheme!.windowOpacity, .9);
      expect(easy.colors.keys, initial.colors.keys);
      expect(easy.window('main').colors, isEmpty);
      expect(easy.window('main').width, 1000);
      expect(easy.window('main').background, isNotNull);
      expect(easy.window('main').elements['editor']!.x, 14);
      final background = easy.withWindow(
        'main',
        easy.window('main').copyWith(background: image()),
      );
      expect(
        SynapseThemeCatalog.colorsForTheme(
              background,
              InterfacePreset.orion,
              'main',
            )['background']! >>
            24,
        0,
      );
    },
  );

  testWidgets(
    'Orion follows system brightness without stale Studio palette caching',
    (tester) async {
      final c = controller();
      final dispatcher = tester.binding.platformDispatcher;
      addTearDown(dispatcher.clearPlatformBrightnessTestValue);
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      c.setOrionTheme(
        OrionThemePreferences.defaults.copyWith(themeMode: ThemeMode.system),
      );
      final dark = SynapseThemeCatalog.current(c, InterfacePreset.orion);
      expect(
        Color(dark.colors['background']!).computeLuminance(),
        lessThan(.5),
      );
      dispatcher.platformBrightnessTestValue = Brightness.light;
      final light = SynapseThemeCatalog.current(c, InterfacePreset.orion);
      expect(
        Color(light.colors['background']!).computeLuminance(),
        greaterThan(.5),
      );
      expect(identical(dark, light), isFalse);
    },
  );

  test('imported window dimensions respect the actual native minimums', () {
    final imported = SynapseStudioTheme(
      windows: {
        'main': SynapseStudioWindow(width: 320, height: 180),
        'settings': SynapseStudioWindow(
          width: 500,
          height: 300,
          colors: {'topBar.text': 0xffabcdef},
          elements: {'settingsControls': SynapseStudioElement(x: 14)},
        ),
      },
    );
    final normalized = SynapseThemeCatalog.normalizeForPreset(
      imported,
      InterfacePreset.synapseV3,
    );
    expect(normalized.window('main').width, 720);
    expect(normalized.window('main').height, 400);
    expect(normalized.window('settings').width, isNull);
    expect(normalized.window('settings').height, isNull);
    expect(normalized.window('settings').colors['topBar.text'], 0xffabcdef);
    expect(normalized.window('settings').elements['settingsControls']!.x, 14);
    expect(imported.window('main').width, 320);
  });

  test(
    'embedded pages share main dimensions and the V3 console stays docked',
    () {
      final document = SynapseStudioTheme(
        windows: {
          'main': SynapseStudioWindow(width: 1000, height: 600),
          'settings': SynapseStudioWindow(width: 400, height: 400),
          'console': SynapseStudioWindow(
            elements: {'consoleOutput': SynapseStudioElement(height: 250)},
          ),
        },
      );
      for (final id in ['settings', 'scriptHub', 'console']) {
        expect(
          SynapseThemeCatalog.windowSize(
            document,
            InterfacePreset.synapseBlue,
            id,
          ),
          const Size(1000, 600),
        );
      }
      expect(
        SynapseThemeCatalog.windowSize(
          document,
          InterfacePreset.synapseV3,
          'console',
          consoleHeight: 180,
        ),
        const Size(1000, 250),
      );
      final withoutConsole = document.withWindow(
        'console',
        SynapseStudioWindow(),
      );
      expect(
        SynapseThemeCatalog.windowSize(
          withoutConsole,
          InterfacePreset.synapseV3,
          'console',
          consoleHeight: 1000,
        ),
        const Size(1000, 400),
      );
      expect(
        SynapseThemeCatalog.windowSize(
          document,
          InterfacePreset.synapseX,
          'settings',
        ),
        const Size(400, 400),
      );
    },
  );

  testWidgets(
    'runtime geometry actually moves and resizes interactive children, opacity zero disables taps',
    (tester) async {
      final c = controller();
      final doc = SynapseThemeCatalog.defaults(InterfacePreset.synapseX)
          .withElement(
            'main',
            'executeButton',
            SynapseStudioElement(
              x: 40,
              y: 12,
              width: 80,
              height: 40,
              opacity: .8,
              radius: 10,
            ),
          );
      commit(c, InterfacePreset.synapseX, doc);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 200,
                height: 100,
                child: SynapseThemeElement(
                  controller: c,
                  preset: InterfacePreset.synapseX,
                  windowId: 'main',
                  elementId: 'executeButton',
                  child: GestureDetector(
                    key: const ValueKey('hit'),
                    onTap: () => taps++,
                    child: const SizedBox(
                      width: 100,
                      height: 50,
                      child: ColoredBox(color: Colors.blue),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('hit'))),
        const Rect.fromLTWH(40, 12, 80, 40),
      );
      await tester.tap(find.byKey(const ValueKey('hit')));
      expect(taps, 1);
      commit(
        c,
        InterfacePreset.synapseX,
        doc.withElement(
          'main',
          'executeButton',
          doc.window('main').elements['executeButton']!.copyWith(opacity: 0),
        ),
      );
      await tester.pump();
      await tester.tapAt(const Offset(80, 32));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real OG controls consume per-element fill, text, border, radius and global font',
    (tester) async {
      final c = controller();
      commit(
        c,
        InterfacePreset.synapse2017,
        SynapseThemeCatalog.defaults(InterfacePreset.synapse2017)
            .copyWith(fontFamily: 'RobotoFlex')
            .withElement(
              'main',
              'executeButton',
              SynapseStudioElement(
                fill: 0xff123456,
                foreground: 0xffabcdef,
                border: 0xff778899,
                radius: 11,
              ),
            ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SynapseThemeElement(
              controller: c,
              preset: InterfacePreset.synapse2017,
              windowId: 'main',
              elementId: 'executeButton',
              child: OgButton(
                'Run',
                theme: OgTheme(const {}),
                width: 100,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      final button = tester.widget<TextButton>(find.byType(TextButton));
      expect(
        button.style!.backgroundColor!.resolve({}),
        const Color(0xff123456),
      );
      expect(
        button.style!.foregroundColor!.resolve({}),
        const Color(0xffabcdef),
      );
      expect(button.style!.side!.resolve({})!.color, const Color(0xff778899));
      expect(
        (button.style!.shape!.resolve({})! as RoundedRectangleBorder)
            .borderRadius,
        BorderRadius.circular(11),
      );
      final text = tester.widget<Text>(find.text('Run'));
      expect(
        text.style?.fontFamily ??
            button.style!.textStyle!.resolve({})!.fontFamily,
        'RobotoFlex',
      );
    },
  );

  testWidgets(
    'background/overlay images pass pointers through and custom logos restore fallback live',
    (tester) async {
      final c = controller();
      final doc = SynapseThemeCatalog.defaults(InterfacePreset.synapseX)
          .withWindow(
            'main',
            SynapseStudioWindow(
              background: image(opacity: .3),
              overlay: image(opacity: .5),
              logo: image(fit: 'contain'),
            ),
          );
      commit(c, InterfacePreset.synapseX, doc);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SynapseThemeSurface(
              controller: c,
              preset: InterfacePreset.synapseX,
              windowId: 'main',
              child: SizedBox(
                width: 300,
                height: 200,
                child: Column(
                  children: [
                    SizedBox(
                      width: 100,
                      height: 40,
                      child: SynapseThemeLogo(
                        controller: c,
                        preset: InterfacePreset.synapseX,
                        windowId: 'main',
                        child: const Text('default-logo'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => taps++,
                      child: const Text('Clickable'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('default-logo'), findsNothing);
      await tester.tap(find.text('Clickable'));
      expect(taps, 1);
      c.setInterfacePreference(InterfacePreset.synapseX, 'themeStudio', null);
      await tester.pumpAndSettle();
      expect(find.text('default-logo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
