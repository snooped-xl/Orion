import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/remote_script.dart';
import 'package:orion/services/script_hub_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/synapse_og/synapse_og_shell.dart';
import 'package:orion/synapse_og/og_pages.dart';
import 'package:orion/synapse_og/og_theme.dart';
import 'package:orion/synapse_og/og_window_geometry.dart';

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
    items: [
      RemoteScript(
        id: provider.name,
        provider: provider,
        title: '${provider.label} example',
        game: 'Fixture',
        description: 'Fixture',
        body: 'print("${provider.name}")',
        externalUrl: 'https://${provider.domain}',
      ),
    ],
    hasMore: false,
  );
  @override
  Future<String> loadScript(RemoteScript script) async =>
      script.body ?? 'print("exact")';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('SynapseInter');
    for (final name in ['Regular', 'Medium', 'Semibold', 'Bold']) {
      loader.addFont(
        rootBundle.load('assets/synapse_v3/fonts/Inter-$name.ttf'),
      );
    }
    await loader.load();
    final mono = FontLoader('JetBrainsMono')
      ..addFont(rootBundle.load('assets/fonts/JetBrainsMono.ttf'));
    await mono.load();
    await rootBundle.loadString('assets/synapse_og/scriptDumperLegacy.lua');
  });
  Future<void> mount(
    WidgetTester tester,
    OrionController controller, {
    bool intro = false,
    VoidCallback? complete,
    GlobalKey<SynapseOgShellState>? key,
    VoidCallback? back,
  }) async {
    await tester.runAsync(
      () => rootBundle.loadString('assets/synapse_og/scriptDumperLegacy.lua'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SynapseOgShell(
            key: key,
            controller: controller,
            nativeWindow: false,
            playIntro: intro,
            onIntroCompleted: complete,
            onBackToOrion: back ?? () {},
          ),
        ),
      ),
    );
  }

  void size(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test(
    'OG native loader expansion keeps its centre and clamps source panels to the work area',
    () {
      const workArea = Rect.fromLTWH(0, 0, 1440, 940);
      const loader = Rect.fromLTWH(587.5, 384.5, 265, 171);
      final main = ogWindowBounds(
        anchor: loader,
        size: OgGeometry.main,
        workAreas: [workArea],
      );
      expect(main, const Rect.fromLTWH(301, 284, 838, 372));
      expect(main.center, loader.center);
      final settings = ogWindowBounds(
        anchor: main,
        size: OgGeometry.settings,
        workAreas: [workArea],
      );
      expect(settings.size, OgGeometry.settings);
      expect(settings.center, main.center);
      final nearEdge = ogWindowBounds(
        anchor: const Rect.fromLTWH(587, 384, 838, 372),
        size: OgGeometry.settings,
        workAreas: [workArea],
      );
      expect(nearEdge.bottom, lessThanOrEqualTo(workArea.bottom));
      expect(nearEdge.right, lessThanOrEqualTo(workArea.right));
      final negativeMonitor = ogWindowBounds(
        anchor: const Rect.fromLTWH(-160, 780, 265, 171),
        size: OgGeometry.settings,
        workAreas: [const Rect.fromLTWH(-1440, 24, 1440, 916), workArea],
      );
      expect(negativeMonitor.left, greaterThanOrEqualTo(-1440));
      expect(negativeMonitor.right, lessThanOrEqualTo(0));
      expect(negativeMonitor.top, greaterThanOrEqualTo(24));
      expect(negativeMonitor.bottom, lessThanOrEqualTo(940));
      final small = ogWindowBounds(
        anchor: const Rect.fromLTWH(100, 200, 838, 372),
        size: OgGeometry.settings,
        workAreas: [const Rect.fromLTWH(0, 24, 1024, 576)],
      );
      expect(small.height, 576);
      expect(small.top, 24);
    },
  );
  test(
    'OG theme preserves source defaults, validates corrupt values and source JSON roundtrips',
    () {
      final t = OgTheme({
        'theme': {
          'windowBg': '#123456',
          'buttonBg': 0xffabcdef,
          'overlayOpacity': 999,
          'scriptList': {'rowText': '#112233'},
          'editorBg': 'bad',
        },
      });
      expect(t.window, const Color(0xff123456));
      expect(t.color('buttonBg'), const Color(0xffabcdef));
      expect(t.opacity, 1);
      expect(t.editor, const Color(0xff232323));
      expect(t.data['windowBg'], isA<int>());
      expect(t.color('scriptList.rowText'), const Color(0xff112233));
      final roundtrip = OgTheme({'theme': OgTheme.decode(t.encode())});
      expect(roundtrip.data, t.data);
      expect(() => OgTheme.decode('[]'), throwsFormatException);
      final invalidEnums = OgTheme({
        'theme': {'logoMode': 'top', 'overlayMode': 'image'},
      });
      expect(invalidEnums.data['logoMode'], 'image');
      expect(invalidEnums.data['overlayMode'], 'behind');
    },
  );
  test(
    'OG preferences persist separately without changing V3 theme or dirty code',
    () async {
      final dir = await Directory.systemTemp.createTemp('orion-og-');
      final first = OrionController(storageDirectory: dir);
      await first.initialize();
      first.updateDocumentContent(first.activeDocumentId, 'print("kept")');
      first.setInterfacePreference(
        InterfacePreset.synapse2017,
        'minimap',
        true,
      );
      first.setInterfacePreference(
        InterfacePreset.synapse2017,
        'theme',
        OgTheme({
          'theme': {'panelBg': 0xff333333},
        }).data,
      );
      await first.flushPersistence();
      first.dispose();
      await first.flushPersistence();
      final second = OrionController(storageDirectory: dir);
      await second.initialize();
      expect(
        second.getInterfacePreferences(InterfacePreset.synapse2017)['minimap'],
        true,
      );
      expect(
        OgTheme(
          second.getInterfacePreferences(InterfacePreset.synapse2017),
        ).panel,
        const Color(0xff333333),
      );
      expect(second.synapsePreferences.themePreset, 'framework');
      expect(second.activeDocument.content, 'print("kept")');
      second.dispose();
      await second.flushPersistence();
      await dir.delete(recursive: true);
    },
  );
  testWidgets(
    'OG default main geometry is source exact and unattached Execute is disabled',
    (tester) async {
      size(tester, OgGeometry.main);
      final c = OrionController();
      addTearDown(c.dispose);
      await mount(tester, c);
      await tester.pumpAndSettle();
      final execute = find.byKey(const ValueKey('og-action/Execute'));
      final rect = tester.getRect(execute);
      expect(rect, const Rect.fromLTWH(9, 323, 116, 39));
      expect(tester.getRect(find.byKey(const ValueKey('code-editor'))).top, 88);
      expect(find.text('Settings & Clients'), findsOneWidget);
      expect(find.text('Back to Orion'), findsNothing);
      expect(find.text('AI'), findsNothing);
      final button = tester.widget<TextButton>(
        find.descendant(of: execute, matching: find.byType(TextButton)),
      );
      expect(button.onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('code-editor')),
        'local kept = 17',
      );
      expect(c.activeDocument.content, 'local kept = 17');
      await tester.tap(find.byTooltip('Add script tab'));
      await tester.pumpAndSettle();
      expect(c.documents, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await c.flushPersistence();
    },
  );
  testWidgets(
    'OG loading uses original card and completes once after the finite animation',
    (tester) async {
      size(tester, OgGeometry.loading);
      final c = OrionController();
      addTearDown(c.dispose);
      var count = 0;
      await mount(tester, c, intro: true, complete: () => count++);
      expect(find.textContaining('[ Loading'), findsOneWidget);
      expect(find.byKey(const ValueKey('code-editor')), findsNothing);
      await tester.pump(const Duration(milliseconds: 1800));
      expect(count, 0);
      size(tester, OgGeometry.main);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(count, 1);
      expect(find.byKey(const ValueKey('code-editor')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(count, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final viewport in [
    const Size(838, 372),
    const Size(670.4, 297.6),
    const Size(1047.5, 465),
  ]) {
    testWidgets('OG footer and editor remain reachable at $viewport', (
      tester,
    ) async {
      size(tester, viewport);
      final c = OrionController();
      addTearDown(c.dispose);
      await mount(tester, c);
      await tester.pumpAndSettle();
      for (final action in [
        'Execute',
        'Clear',
        'Open File',
        'Attach',
        'Script Hub',
        'Settings & Clients',
      ]) {
        expect(find.byKey(ValueKey('og-action/$action')), findsOneWidget);
      }
      final last = tester.getRect(
        find.byKey(const ValueKey('og-action/Settings & Clients')),
      );
      expect(last.bottom, lessThan(viewport.height));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('OG settings preferences and returning to editor preserve code', (
    tester,
  ) async {
    size(tester, OgGeometry.settings);
    final c = OrionController();
    addTearDown(c.dispose);
    c.updateDocumentContent(c.activeDocumentId, '-- keep this');
    await c.flushPersistence();
    final key = GlobalKey<SynapseOgShellState>();
    var backed = false;
    await mount(tester, c, key: key, back: () => backed = true);
    await tester.pumpAndSettle();
    await key.currentState!.openPage(OgPage.settings);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top Most'));
    await tester.pumpAndSettle();
    expect(
      c.getInterfacePreferences(InterfacePreset.synapse2017)['alwaysOnTop'],
      true,
    );
    await tester.tap(find.text('Minimap'));
    await tester.pumpAndSettle();
    expect(
      c.getInterfacePreferences(InterfacePreset.synapse2017)['minimap'],
      true,
    );
    await tester.tap(find.text('Theme Studio'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('synapse-theme-studio')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('synapse-theme-studio')),
        matching: find.text('Theme Studio'),
      ),
      findsOneWidget,
    );
    expect(find.text('Error Logging'), findsNothing);
    await tester.tap(find.byTooltip('Close studio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    expect(c.activeDocument.content, '-- keep this');
    expect(find.byKey(const ValueKey('code-editor')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('og-action/Settings & Clients')),
    );
    await tester.pumpAndSettle();
    final back = find.byKey(const ValueKey('og-back-to-orion'));
    await tester.ensureVisible(back);
    await tester.pumpAndSettle();
    expect(find.text('Back to Orion'), findsOneWidget);
    await tester.tap(back);
    expect(backed, isTrue);
    expect(c.activeDocument.content, '-- keep this');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await c.flushPersistence();
  });
  for (final scale in [1.0, .8, 1.25]) {
    for (final page in [OgPage.settings, OgPage.hub, OgPage.console]) {
      testWidgets('OG $page respects its source panel size at $scale scale', (
        tester,
      ) async {
        size(tester, OgGeometry.size(page) / scale);
        final c = OrionController(scriptHubService: _Hub());
        addTearDown(c.dispose);
        c.updateDocumentContent(
          c.activeDocumentId,
          '-- preserved across source panels',
        );
        await c.flushPersistence();
        final key = GlobalKey<SynapseOgShellState>();
        await mount(tester, c, key: key);
        await tester.pumpAndSettle();
        await key.currentState!.openPage(page);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (page == OgPage.settings) {
          expect(find.text('Top Most'), findsOneWidget);
          expect(find.text('Theme Studio'), findsOneWidget);
          expect(find.text('Error Logging'), findsNothing);
          expect(tester.takeException(), isNull);
        }
        if (page == OgPage.hub) {
          expect(find.text('Dark Dex'), findsOneWidget);
          final run = tester.getRect(
            find.widgetWithText(TextButton, 'Run Script'),
          );
          expect(run.bottom, lessThan(OgGeometry.hub.height / scale));
          await tester.tap(find.text('Script Search'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        if (page == OgPage.console) {
          expect(find.text('F9 Console'), findsOneWidget);
          expect(
            find.textContaining('Connect a client with Orion Bridge'),
            findsOneWidget,
          );
        }
        key.currentState!.handleEditorShortcut('show-editor');
        await tester.pumpAndSettle();
        expect(c.activeDocument.content, '-- preserved across source panels');
        expect(find.byKey(const ValueKey('code-editor')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await c.flushPersistence();
      });
    }
  }
  testWidgets('OG retires legacy live edit in favor of Theme Studio', (
    tester,
  ) async {
    size(tester, OgGeometry.main);
    final c = OrionController();
    addTearDown(c.dispose);
    c.setInterfacePreference(InterfacePreset.synapse2017, 'liveEdit', true);
    await c.flushPersistence();
    await mount(tester, c);
    await tester.pumpAndSettle();
    expect(find.text('LIVE EDIT'), findsNothing);
    await tester.tapAt(const Offset(200, 30), buttons: 2);
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await c.flushPersistence();
  });
  testWidgets('OG loading cancels completion when the shell is disposed', (
    tester,
  ) async {
    size(tester, OgGeometry.loading);
    final c = OrionController();
    addTearDown(c.dispose);
    var completed = 0;
    await mount(tester, c, intro: true, complete: () => completed++);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(completed, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'OG bundled hub uses source list/image/buttons and exact source opens',
    (tester) async {
      size(tester, OgGeometry.hub);
      final c = OrionController(scriptHubService: _Hub());
      addTearDown(c.dispose);
      String? opened;
      await tester.runAsync(
        () => rootBundle.loadString('assets/synapse_og/scriptDumperLegacy.lua'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: OgHubPage(
              controller: c,
              theme: OgTheme(const {}),
              onClose: () {},
              bridgeReady: false,
              onOpen: (script) async {
                opened = await c.loadRemoteScript(script);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dark Dex'), findsOneWidget);
      expect(
        tester.getSize(find.widgetWithText(TextButton, 'Dark Dex')).height,
        27.125,
      );
      expect(tester.getRect(find.text('Universal Explorer')).left, 297);
      expect(ogText(13).letterSpacing, 0);
      expect(find.text('Run Script'), findsOneWidget);
      expect(find.text('Script Search'), findsOneWidget);
      final sourceLabel = tester.getRect(find.text('Script Search'));
      expect(sourceLabel.left, 19);
      expect(sourceLabel.top, 120);
      expect(sourceLabel.height, 32);
      expect(tester.getRect(find.byType(Image).first).top, 63);
      await tester.tapAt(const Offset(400, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open in editor'));
      await tester.pumpAndSettle();
      expect(opened, contains('BypassedDarkDexV3.lua'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
