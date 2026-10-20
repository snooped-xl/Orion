import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart';
import 'package:orion/models/orion_models.dart';
import 'package:orion/models/remote_script.dart';
import 'package:orion/services/script_hub_service.dart';
import 'package:orion/screens/theme_control_screen.dart';
import 'package:orion/state/orion_controller.dart';

const _editorKey = ValueKey('code-editor');

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
      final loader = FontLoader(font.$1);
      loader.addFont(rootBundle.load(font.$2));
      await loader.load();
    }
  });

  testWidgets('first-launch guide enters the editor after completion', (
    tester,
  ) async {
    final app = await _mount(tester, showIntro: true);
    try {
      expect(find.text('Welcome to Orion'), findsOneWidget);
      expect(find.byKey(_editorKey), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(app.controller.introCompleted, isFalse);
      for (var step = 0; step < 3; step++) {
        await tester.tap(find.byKey(const ValueKey('onboarding-next')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Open Orion'));
      await tester.pumpAndSettle();
      expect(app.controller.introCompleted, isTrue);
      expect(find.byTooltip('Editor'), findsOneWidget);
      expect(find.byKey(_editorKey), findsOneWidget);
    } finally {
      await app.dispose(tester);
    }
  });

  testWidgets(
    'editor keeps tab contents and confirms discarding dirty changes',
    (tester) async {
      final app = await _mount(tester);
      try {
        const originalEdit = '-- an idea worth keeping\nprint("hello, Orion")';
        await tester.enterText(find.byKey(_editorKey), originalEdit);
        await tester.pumpAndSettle();
        expect(app.controller.activeDocument.content, originalEdit);
        expect(app.controller.activeDocument.isDirty, isTrue);

        await _shortcut(tester, LogicalKeyboardKey.keyN);
        await tester.pumpAndSettle();
        expect(app.controller.documents, hasLength(2));
        expect(app.controller.activeDocument.content, isEmpty);
        await tester.enterText(
          find.byKey(_editorKey),
          '-- temporary experiment',
        );
        await tester.pumpAndSettle();
        expect(app.controller.activeDocument.name, 'untitled.lua');
        expect(app.controller.activeDocument.isDirty, isTrue);

        final closeTab = find.byTooltip('Close untitled.lua');
        await tester.tap(closeTab);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.text('Save changes?'), findsOneWidget);
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();
        expect(app.controller.documents, hasLength(2));
        expect(
          app.controller.activeDocument.content,
          '-- temporary experiment',
        );

        await tester.tap(closeTab);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(app.controller.documents, hasLength(1));
        expect(app.controller.activeDocument.content, originalEdit);
        final editor = tester.widget<TextField>(find.byKey(_editorKey));
        expect(editor.controller!.text, originalEdit);
        expect(find.text('Save changes?'), findsNothing);
      } finally {
        await app.dispose(tester);
      }
    },
  );

  testWidgets(
    'remote library queries sources, paginates, saves favorites, copies and imports code',
    (tester) async {
      final fixture = _ScriptFixture();
      final app = await _mount(tester, transport: fixture.call);
      try {
        await tester.tap(find.byTooltip('Scripts'));
        await tester.pumpAndSettle();
        expect(fixture.requests, isEmpty);
        expect(find.text('Glass panel'), findsNothing);
        expect(find.text('Orbit canvas'), findsNothing);

        await tester.enterText(_fieldWithHint('Search scripts'), 'orbit');
        await tester.tap(find.widgetWithText(FilledButton, 'Search'));
        await tester.pumpAndSettle();
        expect(app.controller.remoteScripts, hasLength(4));
        expect(fixture.requests.map((uri) => uri.host).toSet(), {
          'robloxscripts.com',
          'scriptblox.com',
          'haxhell.com',
          'rscripts.net',
        });
        expect(
          fixture.requests.every((uri) => uri.queryParameters['q'] == 'orbit'),
          isTrue,
        );
        expect(find.text('Powered by ScriptBlox.com'), findsOneWidget);
        expect(find.text('Data from robloxscripts.com'), findsOneWidget);

        await tester.ensureVisible(find.text('Load more'));
        await tester.tap(find.text('Load more'));
        await tester.pumpAndSettle();
        expect(find.text('Orbit result 2'), findsOneWidget);
        expect(
          fixture.requests.any(
            (uri) =>
                uri.host == 'scriptblox.com' &&
                uri.queryParameters['page'] == '2',
          ),
          isTrue,
        );
        expect(find.text('Load more'), findsNothing);

        await tester.ensureVisible(
          find.widgetWithText(FilterChip, 'ScriptBlox'),
        );
        await tester.tap(find.widgetWithText(FilterChip, 'ScriptBlox'));
        await tester.pumpAndSettle();
        expect(app.controller.selectedProvider, ScriptProvider.scriptBlox);
        expect(app.controller.remoteScripts, hasLength(1));
        expect(
          app.controller.remoteScripts.single.provider,
          ScriptProvider.scriptBlox,
        );
        await tester.tap(find.byTooltip('Add to favorites'));
        await tester.pumpAndSettle();
        expect(
          app.controller.isRemoteFavorite('scriptBlox:fixture-blox-1'),
          isTrue,
        );

        final requestCount = fixture.requests.length;
        await tester.tap(find.widgetWithText(FilterChip, 'Favorites'));
        await tester.pumpAndSettle();
        await tester.enterText(_fieldWithHint('Search favorites'), 'missing');
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('No matching favorites'), findsOneWidget);
        expect(fixture.requests, hasLength(requestCount));
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(find.text('Orbit result 1'), findsOneWidget);

        await tester.tap(find.text('View code'));
        await tester.pumpAndSettle();
        expect(find.text('Open in workspace'), findsOneWidget);
        expect(find.byType(SelectableText), findsOneWidget);
        String? copiedSource;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                copiedSource = (call.arguments as Map)['text'] as String;
              }
              return null;
            });
        await tester.tap(find.text('Copy code'));
        await tester.pumpAndSettle();
        expect(copiedSource, _remoteFixtureSource);

        await tester.tap(find.text('Open in workspace'));
        await tester.pumpAndSettle();
        expect(app.controller.documents, hasLength(2));
        expect(app.controller.activeDocument.name, 'Orbit result 1.lua');
        expect(app.controller.activeDocument.content, _remoteFixtureSource);
        expect(find.byKey(_editorKey), findsOneWidget);
        expect(find.text('Open in workspace'), findsNothing);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
        await app.dispose(tester);
      }
    },
  );

  testWidgets(
    'remote library keeps healthy results while unavailable sources and code retry independently',
    (tester) async {
      final fixture = _ScriptFixture(
        holdListing: true,
        holdCode: true,
        failHaxOnce: true,
        failCodeOnce: true,
      );
      final app = await _mount(tester, transport: fixture.call);
      try {
        await tester.tap(find.byTooltip('Scripts'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Search'));
        await tester.pump();
        expect(app.controller.remoteLoading, isTrue);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.text('HaxHell unavailable'), findsOneWidget);
        expect(find.text('RobloxScripts result 1'), findsOneWidget);
        fixture.releaseListing();
        await tester.pumpAndSettle();
        expect(app.controller.remoteLoading, isFalse);
        expect(find.text('Orbit result 1'), findsOneWidget);
        expect(find.text('HaxHell unavailable'), findsOneWidget);
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('HaxHell unavailable'), findsNothing);
        expect(find.text('HaxHell result 1'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilterChip, 'ScriptBlox'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('View code'));
        await tester.pump();
        expect(find.text('Loading script code…'), findsOneWidget);
        fixture.releaseCode();
        await tester.pumpAndSettle();
        expect(find.text('Could not load code'), findsOneWidget);
        expect(find.text('ScriptBlox returned HTTP 503.'), findsOneWidget);
        await tester.tap(find.text('Retry loading'));
        await tester.pumpAndSettle();
        expect(find.text('Could not load code'), findsNothing);
        expect(find.byType(SelectableText), findsOneWidget);
        expect(fixture.codeRequests, 2);
        await tester.tap(find.byTooltip('Close code'));
        await tester.pumpAndSettle();
        expect(find.text('Open in workspace'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await app.dispose(tester);
      }
    },
  );

  testWidgets(
    'hub Execute loads and retries source without importing or replacing edits',
    (tester) async {
      final fixture = _ScriptFixture(holdCode: true, failCodeOnce: true);
      final app = await _mount(tester, transport: fixture.call);
      try {
        final original = app.controller.activeDocument;
        const source = '-- keep my unsaved editor\nprint("preserved")';
        app.controller.updateDocumentContent(original.id, source);
        await tester.tap(find.byTooltip('Scripts'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilterChip, 'ScriptBlox'));
        await tester.pumpAndSettle();
        final execute = find.byKey(
          const ValueKey('execute/scriptBlox:fixture-blox-1'),
        );
        await tester.ensureVisible(execute);
        await tester.tap(execute);
        await tester.pump();
        expect(tester.widget<FilledButton>(execute).onPressed, isNull);
        expect(fixture.codeRequests, 1);
        expect(
          app.controller.activities.where(
            (entry) => entry.kind == ActivityKind.execution,
          ),
          isEmpty,
        );
        fixture.releaseCode();
        await tester.pumpAndSettle();
        expect(find.text('Retry'), findsOneWidget);
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(fixture.codeRequests, 2);
        expect(app.controller.documents, hasLength(1));
        expect(app.controller.activeDocument.id, original.id);
        expect(app.controller.activeDocument.content, source);
        expect(_fieldWithHint('Search scripts'), findsOneWidget);
        final execution = app.controller.activities.firstWhere(
          (entry) => entry.kind == ActivityKind.execution,
        );
        expect(execution.title, 'No clients connected');
        expect(execution.detail, contains('Orbit result 1'));

        await tester.tap(find.text('View code'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('execute/dialog')));
        await tester.pumpAndSettle();
        expect(
          fixture.codeRequests,
          2,
          reason: 'Code is reused from the cache',
        );
        expect(find.byTooltip('Close code'), findsOneWidget);
        expect(app.controller.documents, hasLength(1));
        expect(app.controller.activeDocument.content, source);
        expect(
          app.controller.activities.where(
            (entry) => entry.kind == ActivityKind.execution,
          ),
          hasLength(2),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await app.dispose(tester);
      }
    },
  );

  testWidgets(
    'Theme Control changes the rendered theme and motion preference',
    (tester) async {
      final app = await _mount(tester);
      try {
        await tester.tap(find.byTooltip('Theme Control'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('theme-layout-controls')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Layout & motion'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Light'));
        await tester.tap(find.text('Light'));
        await tester.pumpAndSettle();
        expect(app.controller.themeMode, ThemeMode.light);
        final settingsContext = tester.element(find.byType(ThemeControlScreen));
        expect(Theme.of(settingsContext).brightness, Brightness.light);

        final motionRow = find
            .ancestor(
              of: find.text('Reduce motion'),
              matching: find.byType(Row),
            )
            .first;
        final motionSwitch = find.descendant(
          of: motionRow,
          matching: find.byType(Switch),
        );
        await tester.tap(motionSwitch);
        await tester.pumpAndSettle();
        expect(app.controller.reducedMotion, isFalse);
        await tester.tap(motionSwitch);
        await tester.pumpAndSettle();
        expect(app.controller.reducedMotion, isTrue);
      } finally {
        await app.dispose(tester);
      }
    },
  );

  testWidgets('keyboard command palette filters and selects a destination', (
    tester,
  ) async {
    final app = await _mount(tester);
    try {
      await tester.tap(find.byKey(_editorKey));
      await _shortcut(tester, LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      final paletteInput = _fieldWithHint('Search actions');
      expect(paletteInput, findsOneWidget);
      await tester.enterText(paletteInput, 'library');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Script library'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(paletteInput, findsNothing);
      expect(find.text('Scripts'), findsAtLeastNWidgets(1));
      expect(find.byKey(_editorKey), findsNothing);
    } finally {
      await app.dispose(tester);
    }
  });

  testWidgets('editor keyboard shortcuts indent and find the next match', (
    tester,
  ) async {
    final app = await _mount(tester);
    try {
      const source = 'print("needle")\nprint("another line")';
      await tester.enterText(find.byKey(_editorKey), source);
      final editor = tester.widget<TextField>(find.byKey(_editorKey));
      editor.controller!.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(app.controller.activeDocument.content, '  $source');

      await _shortcut(tester, LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      final findInput = _fieldWithHint('Find in script…');
      expect(findInput, findsOneWidget);
      await tester.enterText(findInput, 'needle');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Match found'), findsOneWidget);
      expect(
        editor.controller!.selection.textInside(editor.controller!.text),
        'needle',
      );
      await tester.tap(find.byTooltip('Close find'));
      await tester.pumpAndSettle();
      expect(findInput, findsNothing);
    } finally {
      await app.dispose(tester);
    }
  });

  testWidgets('editor opens client setup and UI Selection offers V3', (
    tester,
  ) async {
    final app = await _mount(tester);
    try {
      await tester.tap(find.text('Execute'));
      await tester.pumpAndSettle();
      expect(app.controller.activities.first.title, 'No clients connected');
      await tester.tap(find.text('Clients'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('bridge-client-manager')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close client manager'));
      await tester.pumpAndSettle();
      expect(
        app.controller.activities
            .where((entry) => entry.kind == ActivityKind.execution)
            .every((entry) => entry.severity != ActivitySeverity.success),
        isTrue,
      );
      expect(find.text('No clients connected'), findsOneWidget);
      final content = app.controller.activeDocument.content;
      await tester.tap(find.byTooltip('UI Selection'));
      await tester.pumpAndSettle();
      expect(find.text('Synapse V3'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('select-interface-synapseV3')),
        findsOneWidget,
      );
      expect(_fieldWithHint('Search interfaces'), findsNothing);
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      expect(find.byKey(_editorKey), findsOneWidget);
      expect(app.controller.activeDocument.content, content);
    } finally {
      await app.dispose(tester);
    }
  });

  testWidgets('interrupted page swaps and intro replay preserve editor state', (
    tester,
  ) async {
    final app = await _mount(tester, reducedMotion: false);
    try {
      const source = 'print("preserved through motion")';
      await tester.enterText(find.byKey(_editorKey), source);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Scripts'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byTooltip('UI Selection'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byTooltip('Editor'));
      await tester.pumpAndSettle();
      expect(app.controller.activeDocument.content, source);
      expect(
        tester.widget<TextField>(find.byKey(_editorKey)).controller!.text,
        source,
      );
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Replay intro'));
      await tester.tap(find.text('Replay intro'));
      await tester.pumpAndSettle();
      expect(app.controller.introCompleted, isTrue);
      for (var step = 0; step < 3; step++) {
        await tester.tap(find.byKey(const ValueKey('onboarding-next')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Open Orion'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsWidgets);
      await tester.tap(find.byTooltip('Editor'));
      await tester.pumpAndSettle();
      expect(find.byKey(_editorKey), findsOneWidget);
      expect(app.controller.activeDocument.content, source);
      expect(tester.takeException(), isNull);
    } finally {
      await app.dispose(tester);
    }
  });

  testWidgets('normal animations preserve the editor and console state', (
    tester,
  ) async {
    final app = await _mount(tester, reducedMotion: false);
    try {
      const source = 'print("animation workflow")';
      await tester.enterText(find.byKey(_editorKey), source);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Scripts'));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(_fieldWithHint('Search scripts'), findsOneWidget);
      await tester.tap(find.byTooltip('Editor'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(_editorKey)).controller!.text,
        source,
      );

      await tester.tap(find.text('Execute'));
      await tester.pumpAndSettle();
      expect(find.text('No clients connected'), findsOneWidget);
      await tester.tap(find.text('Console'));
      await tester.pumpAndSettle();
      expect(find.text('No clients connected'), findsNothing);
      await tester.tap(find.text('Console'));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('No clients connected'), findsOneWidget);
    } finally {
      await app.dispose(tester);
    }
  });
}

Finder _fieldWithHint(String hint) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == hint,
);

Future<_AppHarness> _mount(
  WidgetTester tester, {
  bool showIntro = false,
  bool reducedMotion = true,
  ScriptHttpTransport? transport,
}) async {
  tester.view.physicalSize = const Size(1440, 940);
  tester.view.devicePixelRatio = 1;
  final directory = Directory.systemTemp.createTempSync('orion-widget-test-');
  final controller = _WidgetController(
    storageDirectory: directory,
    scriptHubService: ScriptHubService(
      transport:
          transport ??
          (uri, headers) async =>
              throw const ScriptHubException('No network fixture configured.'),
    ),
  );
  await tester.runAsync(controller.initialize);
  // Measure finite navigation separately from Special's repeating label.
  // The filesystem and looping gradient have dedicated explorer tests.
  if (!reducedMotion) {
    await tester.runAsync(() async {
      await Directory(
        '${controller.scriptLibrary!.directory.path}/Special',
      ).delete(recursive: true);
      await controller.scriptLibrary!.refresh();
    });
  }
  controller.setReducedMotion(reducedMotion);
  if (!showIntro) controller.completeIntro();
  await tester.pumpWidget(
    OrionApp(controller: controller, nativeWindow: false),
  );
  await tester.pumpAndSettle();
  return _AppHarness(controller, directory);
}

Future<void> _shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

class _AppHarness {
  final OrionController controller;
  final Directory directory;

  _AppHarness(this.controller, this.directory);

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      controller.dispose();
      await controller.flushPersistence();
      await directory.delete(recursive: true);
    });
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

/// Persistence is tested with real files in controller_test.dart. Keeping the
/// widget harness in memory avoids asynchronous disk writes in FakeAsync.
class _WidgetController extends OrionController {
  _WidgetController({required super.storageDirectory, super.scriptHubService})
    : super(useMacSploit: false);

  @override
  Future<void> flushPersistence() async {}
}

const _remoteFixtureSource =
    '-- transport fixture\nlocal answer = 42\nprint(answer)\n';

class _ScriptFixture {
  _ScriptFixture({
    this.holdListing = false,
    this.holdCode = false,
    this.failHaxOnce = false,
    this.failCodeOnce = false,
  });

  bool holdListing, holdCode, failHaxOnce, failCodeOnce;
  int codeRequests = 0;
  final List<Uri> requests = [];
  Completer<ScriptHttpResponse>? _listingGate;
  ScriptHttpResponse? _listingResponse;
  Completer<ScriptHttpResponse>? _codeGate;
  ScriptHttpResponse? _codeResponse;

  Future<ScriptHttpResponse> call(Uri uri, Map<String, String> headers) async {
    requests.add(uri);
    if (uri.host == 'scriptblox.com' &&
        uri.path == '/api/script/fixture-blox-1') {
      codeRequests++;
      final response = failCodeOnce
          ? const ScriptHttpResponse(statusCode: 503, body: [])
          : _json({
              'script': {'script': _remoteFixtureSource},
            });
      failCodeOnce = false;
      if (holdCode) {
        holdCode = false;
        _codeResponse = response;
        _codeGate = Completer<ScriptHttpResponse>();
        return _codeGate!.future;
      }
      return response;
    }
    if (uri.host == 'haxhell.com' && failHaxOnce) {
      failHaxOnce = false;
      return const ScriptHttpResponse(statusCode: 503, body: []);
    }
    final page = int.tryParse(uri.queryParameters['page'] ?? '1') ?? 1;
    final ScriptHttpResponse response;
    switch (uri.host) {
      case 'scriptblox.com':
        response = _json({
          'result': {
            'scripts': [
              {
                '_id': 'fixture-blox-$page',
                'title': 'Orbit result $page',
                'description': 'A script returned by the source transport.',
                'game': {'name': 'Test Place'},
                'views': 1200,
                'verified': true,
              },
            ],
            'nextPage': page < 2 ? 2 : null,
          },
        });
      case 'robloxscripts.com':
        response = _json({
          'data': [
            {
              'id': 'fixture-rbx-1',
              'title': 'RobloxScripts result 1',
              'game': {'name': 'Test Place'},
              'rawScriptUrl': 'https://robloxscripts.com/raw/fixture.lua',
            },
          ],
          'pagination': {'hasMore': false},
        });
      case 'haxhell.com':
        response = _json({
          'data': [
            {
              'id': 'fixture-hax-1',
              'title': 'HaxHell result 1',
              'game': {'name': 'Test Place'},
              'links': {
                'raw': 'https://haxhell.com/raw/fixture.lua',
                'webpage': '/script/fixture',
              },
            },
          ],
          'pagination': {'hasMore': false},
        });
      case 'rscripts.net':
        response = _json({
          'scripts': [
            {
              'id': 'fixture-rscripts-1',
              'title': 'Rscripts result 1',
              'game': {'title': 'Test Place'},
              'rawScript': 'https://rscripts.net/raw/fixture.lua',
            },
          ],
          'info': {'maxPages': 1},
        });
      default:
        throw StateError('Unexpected fixture request: $uri');
    }
    if (uri.host == 'scriptblox.com' && holdListing) {
      holdListing = false;
      _listingResponse = response;
      _listingGate = Completer<ScriptHttpResponse>();
      return _listingGate!.future;
    }
    return response;
  }

  void releaseListing() => _listingGate!.complete(_listingResponse!);
  void releaseCode() => _codeGate!.complete(_codeResponse!);

  ScriptHttpResponse _json(Map<String, Object?> value) => ScriptHttpResponse(
    statusCode: 200,
    body: utf8.encode(jsonEncode(value)),
    contentType: 'application/json',
  );
}
