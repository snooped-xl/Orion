import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/remote_script.dart';
import 'package:orion/services/script_hub_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/synapse_v3/synapse_v3_pages.dart';
import 'package:orion/synapse_v3/synapse_v3_preferences.dart';
import 'package:orion/synapse_v3/synapse_v3_theme.dart';
import 'package:orion/synapse_v3/v3_panel_controls.dart';
import 'package:orion/synapse_v3/v3_theme_codec.dart';

class _Hub extends ScriptHubService {
  _Hub()
    : super(
        transport: (_, _) async =>
            const ScriptHttpResponse(statusCode: 200, body: []),
      );
  @override
  Future<ScriptPage> fetch(
    ScriptProvider provider,
    String query,
    int page,
  ) async => ScriptPage(
    items: provider == ScriptProvider.scriptBlox
        ? List.generate(
            12,
            (index) => RemoteScript(
              id: '$page-$index',
              provider: provider,
              title: 'Script $page-$index',
              game: 'Fixture game',
              description: '',
              body: 'print("exact $page-$index")',
              externalUrl: 'https://scriptblox.com/script/$page-$index',
            ),
          )
        : [],
    hasMore: provider == ScriptProvider.scriptBlox && page == 1,
  );
  @override
  Future<String> loadScript(RemoteScript script) async =>
      script.body ?? 'print("exact ${script.id}")';
}

Widget _app(OrionController controller, Widget child) => AnimatedBuilder(
  animation: controller,
  builder: (context, _) => MaterialApp(
    theme: V3ThemeData.theme(
      controller.synapsePreferences.themeAccent,
      controller.synapsePreferences.themeBackground,
      legacyFramework:
          controller.synapsePreferences.themePreset == 'legacyFramework',
      overrides: controller.synapsePreferences.themeColors,
      family: controller.synapsePreferences.uiFontFamily,
    ),
    home: Scaffold(body: child),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Inter', 'Rubik']) {
      final loader = FontLoader('Synapse$family');
      for (final weight in ['Regular', 'Medium', 'Semibold', 'Bold']) {
        loader.addFont(
          rootBundle.load('assets/synapse_v3/fonts/$family-$weight.ttf'),
        );
      }
      await loader.load();
    }
    final mono = FontLoader('JetBrainsMono')
      ..addFont(rootBundle.load('assets/fonts/JetBrainsMono.ttf'));
    await mono.load();
  });

  test(
    'V3 preferences validate values without losing valid source token colors',
    () {
      final prefs = SynapsePreferences.fromJson({
        'alwaysOnTop': 'true',
        'resizable': false,
        'minimap': true,
        'themePreset': 'missing',
        'consoleHeight': 9999,
        'consoleFontSize': double.nan,
        'cornerRadius': -2,
        'uiFontFamily': 'unknown',
        'themeColors': {
          'editor.workAreaBg': 0xff123456,
          'scriptList.sections.bookmarks.labelText': 0xffabcdef,
          'shell.pageBg': -1,
          'bad': 'red',
        },
      });
      expect(prefs.alwaysOnTop, isFalse);
      expect(prefs.resizable, isFalse);
      expect(prefs.minimap, isTrue);
      expect(prefs.themePreset, 'framework');
      expect(prefs.consoleHeight, 360);
      expect(prefs.consoleFontSize, 11);
      expect(prefs.cornerRadius, 0);
      expect(prefs.uiFontFamily, 'SynapseInter');
      expect(prefs.themeColors, {
        'editor.workAreaBg': 0xff123456,
        'scriptList.sections.bookmarks.labelText': 0xffabcdef,
      });
    },
  );

  test(
    'V3 manual settings and source theme persist alongside unsaved code',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'orion-v3-prefs-',
      );
      final first = OrionController(storageDirectory: directory);
      await first.initialize();
      final id = first.activeDocument.id;
      first.updateDocumentContent(id, 'print("unsaved")');
      first.updateSynapsePreferences(
        minimap: true,
        showScriptList: false,
        compactButtons: true,
        compactTabs: true,
        consoleTimestamp: false,
        defaultTabContent: '-- new',
        consoleHeight: 190,
        consoleFontSize: 13,
        uiFontFamily: 'SynapseRubik',
      );
      first.resetSynapseTheme(
        preset: 'ocean',
        colors: V3ThemePresets.colors['ocean']!,
      );
      first.updateSynapsePreferences(uiFontFamily: 'SynapseRubik');
      first.updateSynapsePreferences(
        gistUrls: ['https://gist.github.com/example/123'],
        bookmarkedDocumentIds: [id],
        gistDocumentUrls: {id: 'https://gist.github.com/example/123'},
      );
      await first.flushPersistence();
      first.dispose();
      await first.flushPersistence();
      final restored = OrionController(storageDirectory: directory);
      await restored.initialize();
      expect(restored.activeDocument.content, 'print("unsaved")');
      expect(restored.synapsePreferences.minimap, isTrue);
      expect(restored.synapsePreferences.showScriptList, isFalse);
      expect(restored.synapsePreferences.compactButtons, isTrue);
      expect(restored.synapsePreferences.defaultTabContent, '-- new');
      expect(restored.synapsePreferences.themePreset, 'ocean');
      expect(restored.synapsePreferences.uiFontFamily, 'SynapseRubik');
      expect(restored.synapsePreferences.gistUrls, [
        'https://gist.github.com/example/123',
      ]);
      expect(restored.synapsePreferences.bookmarkedDocumentIds, [id]);
      expect(restored.synapsePreferences.gistDocumentUrls, {
        id: 'https://gist.github.com/example/123',
      });
      expect(
        restored.synapsePreferences.themeColors,
        V3ThemePresets.colors['ocean'],
      );
      final saved = jsonDecode(
        await File('${directory.path}/orion-workspace.json').readAsString(),
      );
      expect(saved['synapsePreferences']['consoleTimestamp'], false);
      restored.dispose();
      await restored.flushPersistence();
      await directory.delete(recursive: true);
    },
  );

  test(
    'V3 manual Gist fields reject invalid URLs and cap restored collections',
    () {
      final prefs = SynapsePreferences.fromJson({
        'gistUrls': [
          'file:///private',
          'javascript:alert(1)',
          'https://user:pass@example.com/x',
          'https://gist.github.com/example/123',
          'https://gist.github.com/example/123',
        ],
        'gistDocumentUrls': {
          'valid': 'https://gist.github.com/example/123',
          'bad': 'file:///private',
          'credentials': 'https://user:pass@example.com/x',
        },
        'bookmarkedDocumentIds': List.generate(300, (i) => 'doc-$i'),
      });
      expect(prefs.gistUrls, ['https://gist.github.com/example/123']);
      expect(prefs.gistDocumentUrls, {
        'valid': 'https://gist.github.com/example/123',
      });
      expect(prefs.bookmarkedDocumentIds, hasLength(200));
    },
  );

  test(
    'V3 theme JSON matches source schema and preserves manual preferences',
    () {
      final original =
          const SynapsePreferences(minimap: true, alwaysOnTop: true).copyWith(
            themePreset: 'ocean',
            themeColors: V3ThemePresets.colors['ocean'],
            uiFontFamily: 'SynapseRubik',
            cornerRadius: 11,
          );
      final encoded = V3ThemeCodec.encode(original);
      final payload = jsonDecode(encoded);
      expect(payload['format'], 'synapse-v3-theme');
      expect(payload['theme']['shell']['cornerRadiusPx'], 11);
      final restored = V3ThemeCodec.decode(
        encoded,
        const SynapsePreferences(minimap: true),
      );
      expect(restored.themePreset, 'ocean');
      expect(restored.themeAccent, original.themeAccent);
      expect(restored.uiFontFamily, 'SynapseRubik');
      expect(restored.cornerRadius, 11);
      expect(restored.minimap, isTrue);
      expect(restored.alwaysOnTop, isFalse);
      expect(
        () => V3ThemeCodec.decode('{"format":"unknown"}', original),
        throwsFormatException,
      );
    },
  );

  for (final size in [const Size(961, 417), const Size(576, 276)]) {
    testWidgets(
      'V3 settings scroll and hide removed diagnostics at ${size.width}x${size.height}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = OrionController(scriptHubService: _Hub())
          ..setReducedMotion(true);
        addTearDown(controller.dispose);
        await controller.flushPersistence();
        await tester.pumpWidget(
          _app(controller, SynapseV3SettingsPage(controller: controller)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final minimap = find.byWidgetPredicate(
          (w) => w is V3Checkbox && w.label == 'Minimap',
        );
        await tester.ensureVisible(minimap);
        await tester.pumpAndSettle();
        await tester.tap(minimap);
        await tester.pumpAndSettle();
        expect(controller.synapsePreferences.minimap, isTrue);
        final content = find.byType(TextField);
        await tester.ensureVisible(content);
        await tester.pumpAndSettle();
        await tester.enterText(content, '-- initial tab');
        expect(
          controller.synapsePreferences.defaultTabContent,
          '-- initial tab',
        );
        expect(find.text('Error Logging'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.flushPersistence();
      },
    );
  }

  testWidgets('V3 hub preserves source layout, exact code and API pagination', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(961, 461);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = OrionController(scriptHubService: _Hub());
    addTearDown(controller.dispose);
    String? imported;
    await tester.pumpWidget(
      _app(
        controller,
        Padding(
          padding: const EdgeInsets.only(top: 44),
          child: SynapseV3ScriptHubPage(
            controller: controller,
            onOpenScript: (script) async {
              imported = await controller.loadRemoteScript(script);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.remoteScripts, hasLength(12));
    expect(find.byTooltip('Save favorite'), findsNothing);
    expect(find.byTooltip('Favorites'), findsNothing);
    expect(find.text('All sources'), findsNothing);
    expect(find.byTooltip('Orion Bridge is not attached'), findsWidgets);
    await tester.tap(find.byTooltip('Open in editor').first);
    await tester.pumpAndSettle();
    expect(imported, 'print("exact 1-0")');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);
    expect(controller.remoteScripts, hasLength(24));
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
    await tester.tap(find.text('Synapse Script Hub'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Previous'), findsNothing);
    expect(find.text('Next'), findsNothing);
    expect(find.byTooltip('View on website'), findsNothing);
    expect(find.byTooltip('Open in editor'), findsNWidgets(4));
    final cardRects = [
      for (final id in [
        'synapse-dark-dex',
        'synapse-unnamed-esp',
        'synapse-remote-spy',
        'synapse-script-dumper',
      ])
        tester.getRect(find.byKey(ValueKey('v3-hub/robloxScripts:$id'))),
    ];
    for (final rect in cardRects) {
      expect(rect.top, closeTo(99, .01));
    }
    expect(
      cardRects.first.width / cardRects.first.height,
      closeTo(4 / 3, .001),
    );
    expect(cardRects[1].left - cardRects[0].right, closeTo(8, .01));
    expect(find.textContaining('Dark Dex', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('Script Dumper', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Open in editor').first);
    await tester.pumpAndSettle();
    expect(
      imported,
      'loadstring(game:HttpGet("https://raw.githubusercontent.com/Babyhamsta/RBLX_Scripts/main/Universal/BypassedDarkDexV3.lua", true))()',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.flushPersistence();
  });

  testWidgets(
    'V3 console reports disconnected and Clear removes local log entries',
    (tester) async {
      final controller = OrionController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          controller,
          SizedBox(
            height: 160,
            child: SynapseV3Console(controller: controller),
          ),
        ),
      );
      expect(find.text('Orion Bridge · Not connected'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(controller.activities, isEmpty);
      expect(find.text('No output yet.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.flushPersistence();
    },
  );
}
