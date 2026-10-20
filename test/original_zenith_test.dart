import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_models.dart';
import 'package:orion/original_ports/zenith_pages.dart';
import 'package:orion/original_ports/zenith_shell.dart';
import 'package:orion/original_ports/zenith_ui.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';
import 'package:orion/widgets/monaco_editor.dart';

class _Controller extends OrionController {
  _Controller() : super(useMacSploit: false);

  int opened = 0;
  String? savedBody;
  final savedPaths = <String>[];
  @override
  Future<void> flushPersistence() async {}
  @override
  Future<EditorDocument?> openFile() async {
    opened++;
    return newDocument(name: 'disk.lua', content: 'print("from disk")');
  }

  @override
  Future<bool> saveDocumentToPath(String id, String path) async {
    savedPaths.add(path);
    savedBody = documents.firstWhere((d) => d.id == id).content;
    return true;
  }

  @override
  Future<bool> saveDocument([String? id]) async {
    savedBody = activeDocument.content;
    return true;
  }
}

class _Assets extends EditorAssetServer {
  @override
  Future<Uri> start() async =>
      Uri.parse('http://127.0.0.1:9999/editor/index.html');
  @override
  Future<void> close() async {}
}

class _Channel extends MethodChannel {
  _Channel() : super('orion/original-zenith-test');
  Future<dynamic> Function(MethodCall)? handler;
  final calls = <MethodCall>[];
  Map<String, dynamic>? snapshot;
  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall)? value) =>
      handler = value;
  @override
  Future<T?> invokeMethod<T>(String method, [dynamic args]) async {
    calls.add(MethodCall(method, args));
    if (method == 'create') {
      await handler?.call(MethodCall('message', jsonEncode({'type': 'ready'})));
    }
    if (method == 'send') {
      final command = jsonDecode(args as String) as Map<String, dynamic>;
      if (command['type'] == 'sync') snapshot = command;
      if (command['type'] == 'flush') {
        final doc = (snapshot!['documents'] as List).firstWhere(
          (d) => d['id'] == snapshot!['activeId'],
        );
        await handler?.call(
          MethodCall(
            'message',
            jsonEncode({
              'type': 'flush',
              'requestId': command['requestId'],
              'id': doc['id'],
              'content': doc['content'],
            }),
          ),
        );
      }
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (
        'OriginalNunito',
        'assets/original_zenith/Fonts/Nunito-Source-Regular.ttf',
      ),
      ('JetBrainsMono', 'assets/fonts/JetBrainsMono.ttf'),
      ('OriginalConsolas', 'assets/synapse_x/fonts/LiberationMono-Regular.ttf'),
      ('OriginalSymbols', 'assets/original_fonts/DejaVuSans.ttf'),
      ('OriginalEmoji', 'assets/original_fonts/NotoColorEmoji.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    // Decode the large preserved tables outside a widget test's fake clock.
    await rootBundle.loadString(
      'assets/original_zenith/Data/function-documentation.json',
    );
    await rootBundle.loadString(
      'assets/original_zenith/Data/help-articles.json',
    );
  });
  Future<void> mount(
    WidgetTester tester,
    _Controller c, {
    Size size = const Size(1024, 640),
    bool settle = true,
    bool reduced = true,
    bool native = false,
    MonacoEditorService? service,
    GlobalKey<ZenithShellState>? key,
    VoidCallback? back,
    Future<String?> Function()? pickScriptPath,
    Future<String?> Function(String)? pickSavePath,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    c.setReducedMotion(reduced);
    await tester.runAsync(() => c.initialize());
    final pickerDirectory = Directory.systemTemp.createTempSync(
      'zenith-picker-',
    );
    addTearDown(() => pickerDirectory.deleteSync(recursive: true));
    final pickerFile = File('${pickerDirectory.path}/disk.lua')
      ..writeAsStringSync('print("from disk")');
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: c.reducedMotion),
          child: UiScaleViewport(scale: c.uiScale, child: child!),
        ),
        home: Material(
          type: MaterialType.transparency,
          child: ZenithShell(
            key: key,
            controller: c,
            nativeWindow: native,
            onBackToOrion: back ?? () {},
            editorService: service,
            pickScriptPath:
                pickScriptPath ??
                () async {
                  c.opened++;
                  return pickerFile.path;
                },
            pickSavePath:
                pickSavePath ??
                (_) async => '${pickerDirectory.path}/saved.lua',
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> login(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('zenith-login')));
    await tester.pumpAndSettle();
  }

  Future<void> page(WidgetTester tester, int index) async {
    await tester.tap(find.byKey(ValueKey('zenith-nav-$index')));
    await tester.pumpAndSettle();
  }

  Future<void> waitAssets(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> cleanup(WidgetTester tester, _Controller c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  Finder action(String label) => find.byWidgetPredicate(
    (widget) =>
        widget is ZenithButton && widget.action && widget.label == label,
  );
  Finder input(String hint) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == hint,
  );

  testWidgets(
    'source initialization fades out before the local login and home',
    (tester) async {
      final c = _Controller();
      await mount(tester, c, settle: false, reduced: false);
      expect(find.text('Initializing...'), findsOneWidget);
      expect(find.byKey(const ValueKey('zenith-navigation')), findsNothing);
      await tester.pump(const Duration(milliseconds: 519));
      expect(find.text('Initializing...'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.text('Initializing...'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 90));
      await tester.pumpAndSettle();
      expect(find.text('Initializing...'), findsNothing);
      await tester.enterText(input('Username'), 'local name');
      await tester.enterText(input('••••phrase'), 'local secret');
      await login(tester);
      expect(find.byKey(const ValueKey('zenith-navigation')), findsOneWidget);
      expect(find.text('Changelog'), findsOneWidget);
      expect(find.text('News'), findsOneWidget);
      expect(
        c.getInterfacePreferences(InterfacePreset.zenithV2).values,
        isNot(contains('local secret')),
      );
      expect(find.text('Back to Orion'), findsNothing);
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'editor file controls new tabs clear and native snapshot preserve drafts',
    (tester) async {
      final c = _Controller(), channel = _Channel();
      final service = MonacoEditorService(
        channel: channel,
        server: _Assets(),
        onChange: c.updateDocumentContent,
        onShortcut: (_) {},
      );
      await service.initialize();
      final key = GlobalKey<ZenithShellState>();
      await mount(tester, c, key: key, service: service);
      await login(tester);
      await page(tester, 1);
      final options = channel.snapshot!['options'] as Map;
      expect(options['shell'], 'originalZenith');
      expect(options['fontSize'], 14);
      expect(options['lineHeight'], 20);
      expect(options['background'], '#0d0d0d');
      expect(options['animateReveal'], false);
      expect(tester.widget<ZenithButton>(action('Execute')).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('code-editor')),
        'print("draft one")',
      );
      await tester.pumpAndSettle();
      final first = c.activeDocumentId;
      await tester.tap(find.widgetWithText(ZenithButton, '+'));
      await tester.pumpAndSettle();
      expect(c.documents.length, 2);
      expect(
        c.documents.firstWhere((d) => d.id == first).content,
        'print("draft one")',
      );
      await tester.enterText(
        find.byKey(const ValueKey('code-editor')),
        'print("draft two")',
      );
      await tester.pumpAndSettle();
      await tester.tap(action('Save File'));
      await tester.pumpAndSettle();
      expect(c.savedBody, 'print("draft two")');
      await tester.runAsync(() async {
        await tester.tap(action('Open File'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(c.opened, 1);
      expect(c.activeDocument.content, 'print("from disk")');
      await tester.tap(action('Clear'));
      await tester.pumpAndSettle();
      expect(c.activeDocument.content, '');
      expect(
        c.documents.firstWhere((d) => d.id == first).content,
        'print("draft one")',
      );
      await page(tester, 5);
      expect(find.byKey(const ValueKey('code-editor')), findsNothing);
      key.currentState!.handleEditorShortcut('show-editor');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('code-editor')), findsOneWidget);
      expect(c.documents.length, 3);
      await cleanup(tester, c);
      expect(service.ready, true);
      service.dispose();
    },
  );

  testWidgets(
    'return is in settings and manual interface preferences alter execution',
    (tester) async {
      final c = _Controller();
      var backs = 0;
      await mount(tester, c, back: () => backs++);
      await login(tester);
      await page(tester, 1);
      expect(find.text('Back to Orion'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('code-editor')),
        'print("keep me")',
      );
      await page(tester, 5);
      await tester.ensureVisible(
        find.byKey(const ValueKey('zenith-back-to-orion')),
      );
      await tester.tap(find.byKey(const ValueKey('zenith-back-to-orion')));
      await tester.pumpAndSettle();
      expect(backs, 1);
      expect(c.activeDocument.content, 'print("keep me")');
      await tester.ensureVisible(find.text('Interface Settings'));
      await tester.tap(find.text('Interface Settings'));
      await tester.pumpAndSettle();
      await tester.enterText(input('Search settings...'), 'Hide Save Button');
      await tester.pumpAndSettle();
      expect(find.byType(ZenithToggle), findsOneWidget);
      await tester.tap(find.byType(ZenithToggle));
      await tester.pumpAndSettle();
      expect(
        c.getInterfacePreferences(InterfacePreset.zenithV2)['hideSaveButton'],
        true,
      );
      await tester.enterText(
        input('Search settings...'),
        'Hide Output Console',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ZenithToggle));
      await tester.pumpAndSettle();
      expect(
        c.getInterfacePreferences(
          InterfacePreset.zenithV2,
        )['hideOutputConsole'],
        true,
      );
      await page(tester, 1);
      expect(action('Save File'), findsNothing);
      expect(action('Open File'), findsOneWidget);
      expect(find.text('Script Output'), findsNothing);
      expect(c.activeDocument.content, 'print("keep me")');
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'source navigation expands 56 to 200 and collapses after two seconds',
    (tester) async {
      final c = _Controller();
      await mount(tester, c, reduced: false);
      await login(tester);
      final nav = find.byKey(const ValueKey('zenith-navigation'));
      expect(tester.getSize(nav).width, 56);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(1000, 620));
      await mouse.moveTo(tester.getTopLeft(nav) + const Offset(24, 24));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getSize(nav).width, greaterThan(56));
      expect(tester.getSize(nav).width, lessThan(200));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getSize(nav).width, 200);
      await mouse.moveTo(const Offset(1000, 620));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1900));
      expect(tester.getSize(nav).width, 200);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getSize(nav).width, lessThan(200));
      expect(tester.getSize(nav).width, greaterThan(56));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getSize(nav).width, 56);
      await mouse.removePointer();
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'navigation setting suppresses expansion and page fade preserves editor state',
    (tester) async {
      final c = _Controller()
        ..setInterfacePreference(
          InterfacePreset.zenithV2,
          'navigationSlideOut',
          false,
        );
      await mount(tester, c, reduced: false);
      await login(tester);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(1000, 620));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('zenith-nav-1')));
      await tester.pump();
      final editorBody = find.byKey(const ValueKey('zenith-editor-body'));
      final opacity = find
          .ancestor(of: editorBody, matching: find.byType(Opacity))
          .first;
      expect(tester.widget<Opacity>(opacity).opacity, 0);
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.widget<Opacity>(opacity).opacity, greaterThan(0));
      expect(tester.widget<Opacity>(opacity).opacity, lessThan(1));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      await tester.enterText(
        find.byKey(const ValueKey('code-editor')),
        'print("unchanged")',
      );
      await page(tester, 0);
      await page(tester, 1);
      expect(c.activeDocument.content, 'print("unchanged")');
      await mouse.removePointer();
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'bundled documentation search and expansion show actual source API content',
    (tester) async {
      final c = _Controller();
      await mount(tester, c);
      await login(tester);
      await page(tester, 3);
      await waitAssets(tester);
      expect(find.byType(ZenithDocumentation), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('zenith-doc-category-All')));
      await tester.pumpAndSettle();
      await tester.enterText(input('Search functions...'), 'setfflag');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('zenith-function-setfflag')),
        findsOneWidget,
      );
      expect(
        find.text('Sets a Fast Flag (FFlag) to a specified value.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('zenith-function-setfflag')));
      await tester.pumpAndSettle();
      expect(
        find.text('setfflag(flagName: string, value: any): boolean'),
        findsOneWidget,
      );
      await tester.enterText(
        input('Search functions...'),
        'missing_function_xyz',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('zenith-function-setfflag')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'bundled help search opens source articles with useful tab instructions',
    (tester) async {
      final c = _Controller();
      await mount(tester, c);
      await login(tester);
      await page(tester, 4);
      await waitAssets(tester);
      expect(find.byType(ZenithHelp), findsOneWidget);
      await tester.enterText(input('Search articles...'), 'Working with Tabs');
      await tester.pumpAndSettle();
      final article = find.byKey(
        const ValueKey('zenith-help-article-Working with Tabs'),
      );
      expect(article, findsOneWidget);
      await tester.ensureVisible(article);
      await tester.tap(article);
      await tester.pumpAndSettle();
      final words = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ZenithHelp),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
          .join('');
      expect(
        words,
        contains(
          'Zenith supports multiple editor tabs for organizing scripts and improving workflow.',
        ),
      );
      expect(find.text('Creating Tabs'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'documentation state survives navigation while retained native Monaco stays inactive',
    (tester) async {
      const window = MethodChannel('window_manager');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        window,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          window,
          null,
        ),
      );
      final c = _Controller(), channel = _Channel();
      final service = MonacoEditorService(
        channel: channel,
        server: _Assets(),
        onChange: c.updateDocumentContent,
        onShortcut: (_) {},
      );
      await mount(tester, c, service: service, native: true);
      await login(tester);
      await page(tester, 1);
      await tester.pumpAndSettle();
      expect(service.visible, Platform.isLinux || Platform.isWindows);
      await page(tester, 3);
      await waitAssets(tester);
      expect(service.visible, false);
      expect(find.byType(MonacoEditor), findsNothing);
      expect(
        find.byType(MonacoEditor, skipOffstage: false),
        Platform.isLinux || Platform.isWindows ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('zenith-doc-category-All')));
      await tester.pumpAndSettle();
      await tester.enterText(input('Search functions...'), 'setfflag');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('zenith-function-setfflag')));
      await tester.pumpAndSettle();
      expect(
        find.text('setfflag(flagName: string, value: any): boolean'),
        findsOneWidget,
      );
      await page(tester, 0);
      expect(service.visible, false);
      await page(tester, 1);
      expect(service.visible, Platform.isLinux || Platform.isWindows);
      await page(tester, 3);
      expect(service.visible, false);
      expect(
        tester.widget<TextField>(input('Search functions...')).controller!.text,
        'setfflag',
      );
      expect(
        find.byKey(const ValueKey('zenith-function-setfflag')),
        findsOneWidget,
      );
      expect(
        find.text('setfflag(flagName: string, value: any): boolean'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
      service.dispose();
    },
  );
  testWidgets(
    'selected help article and history survive Home and Execution navigation',
    (tester) async {
      final c = _Controller();
      await mount(tester, c);
      await login(tester);
      await page(tester, 4);
      await waitAssets(tester);
      await tester.enterText(input('Search articles...'), 'Working with Tabs');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('zenith-help-article-Working with Tabs')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Creating Tabs'), findsOneWidget);
      await page(tester, 0);
      await page(tester, 1);
      await page(tester, 4);
      expect(find.text('Creating Tabs'), findsOneWidget);
      final words = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ZenithHelp),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? '')
          .join('');
      expect(
        words,
        contains(
          'Zenith supports multiple editor tabs for organizing scripts and improving workflow.',
        ),
      );
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );

  test(
    'source knowledge datasets are complete offline documents with bundled image references',
    () async {
      final docs =
          jsonDecode(
                await File(
                  'assets/original_zenith/Data/function-documentation.json',
                ).readAsString(),
              )
              as List;
      final help =
          jsonDecode(
                await File(
                  'assets/original_zenith/Data/help-articles.json',
                ).readAsString(),
              )
              as List;
      expect(docs.length, 302);
      expect(help.length, 31);
      expect(
        docs.every(
          (d) =>
              d['name'] is String &&
              d['description'] is String &&
              d['syntax'] is String,
        ),
        true,
      );
      expect(
        help.every(
          (a) =>
              a['title'] is String &&
              a['category'] is String &&
              a['content'] is String,
        ),
        true,
      );
      final imageReferences = <String>{};
      for (final article in help) {
        for (final match in RegExp(
          r'!\[[^\]]*\]\(([^)]+)\)',
        ).allMatches(article['content'] as String)) {
          imageReferences.add(match.group(1)!.split('/').last);
        }
      }
      expect(imageReferences, isNotEmpty);
      for (final name in imageReferences) {
        expect(
          await File('assets/original_zenith/Help/$name').length(),
          greaterThan(0),
        );
      }
    },
  );

  testWidgets(
    'login execution settings documentation and help fit 80 100 and 125 percent',
    (tester) async {
      for (final scale in [.8, 1.0, 1.25]) {
        final c = _Controller()..setUiScale(scale);
        await mount(tester, c, size: const Size(1024, 640));
        expect(tester.takeException(), isNull);
        await login(tester);
        await page(tester, 1);
        expect(find.byKey(const ValueKey('code-editor')), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final index in [3, 4, 5]) {
          await page(tester, index);
          await waitAssets(tester);
          expect(tester.takeException(), isNull);
        }
        await cleanup(tester, c);
      }
    },
  );
  testWidgets(
    'source chrome stays transparent on hover and honors disabled resizing',
    (tester) async {
      const channel = MethodChannel('window_manager');
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'isMaximized') return false;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final c = _Controller()
        ..setInterfacePreference(InterfacePreset.zenithV2, 'resizable', false);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: c.reducedMotion),
            child: UiScaleViewport(scale: c.uiScale, child: child!),
          ),
          home: Material(
            type: MaterialType.transparency,
            child: ZenithShell(
              controller: c,
              nativeWindow: true,
              onBackToOrion: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final maximize = find.descendant(
        of: find.byTooltip('Maximize'),
        matching: find.byType(ZenithButton),
      );
      expect(tester.widget<ZenithButton>(maximize).chrome, true);
      final pointer = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await pointer.addPointer(location: const Offset(0, 0));
      await pointer.moveTo(tester.getCenter(maximize));
      await tester.pumpAndSettle();
      final background = tester.widget<AnimatedContainer>(
        find.descendant(of: maximize, matching: find.byType(AnimatedContainer)),
      );
      expect(
        (background.decoration as BoxDecoration).color,
        Colors.transparent,
      );
      calls.clear();
      await tester.tap(maximize);
      await tester.pumpAndSettle();
      expect(calls, isNot(contains('isMaximized')));
      expect(calls, isNot(contains('maximize')));
      c.setInterfacePreference(InterfacePreset.zenithV2, 'resizable', true);
      await tester.pumpAndSettle();
      await tester.tap(maximize);
      await tester.pumpAndSettle();
      expect(calls, contains('maximize'));
      await pointer.removePointer();
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'source output has a five pixel resize grip, source limits, and local clearing',
    (tester) async {
      final c = _Controller()..executeSource('print("one")', name: 'first.lua');
      final key = GlobalKey<ZenithShellState>();
      await mount(tester, c, key: key);
      await login(tester);
      await page(tester, 1);
      final output = find.byKey(const ValueKey('zenith-output'));
      final grip = find.byKey(const ValueKey('zenith-output-resize'));
      expect(tester.getSize(output).height, 140);
      expect(tester.getSize(grip).height, 5);
      final stackHeight =
          tester
              .getSize(find.byKey(const ValueKey('zenith-editor-body')))
              .height +
          8 +
          140;
      await tester.drag(grip, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.getSize(output).height, closeTo(stackHeight * .65, .01));
      await tester.drag(grip, const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(tester.getSize(output).height, 72);
      final count = c.activities.length;
      final clear = find.descendant(
        of: output,
        matching: find.widgetWithText(ZenithButton, 'Clear'),
      );
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(c.activities, hasLength(count));
      String outputText() => tester
          .widget<SelectableText>(
            find.descendant(of: output, matching: find.byType(SelectableText)),
          )
          .textSpan!
          .toPlainText();
      expect(outputText(), '');
      c.executeSource('print("two")', name: 'second.lua');
      await tester.pumpAndSettle();
      expect(outputText(), contains('run second.lua.'));
      expect(outputText(), isNot(contains('run first.lua.')));
      key.currentState!.handleEditorShortcut('console');
      await tester.pumpAndSettle();
      expect(tester.getSize(output).height, 32);
      expect(grip, findsNothing);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'source closes an active middle tab into its previous neighbor and keeps the last tab',
    (tester) async {
      final c = _Controller();
      await tester.runAsync(() => c.initialize());
      final first = c.activeDocumentId;
      final middle = c.newDocument(name: 'Middle');
      final last = c.newDocument(name: 'Last');
      c.selectDocument(middle.id);
      final key = GlobalKey<ZenithShellState>();
      await mount(tester, c, key: key);
      await login(tester);
      await page(tester, 1);
      key.currentState!.handleEditorShortcut('close-tab');
      await tester.pumpAndSettle();
      expect(c.activeDocumentId, first);
      expect(c.documents.last.id, last.id);
      c.closeDocument(last.id);
      await tester.pumpAndSettle();
      key.currentState!.handleEditorShortcut('close-tab');
      await tester.pumpAndSettle();
      expect(c.documents, hasLength(1));
      expect(c.activeDocumentId, first);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'source file imports always add fresh tabs and Save always shows a picker',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'zenith-source-files-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/source.lua')
        ..writeAsStringSync('print("first")');
      final c = _Controller();
      var savePickers = 0;
      await mount(
        tester,
        c,
        pickScriptPath: () async => file.path,
        pickSavePath: (suggested) async {
          savePickers++;
          expect(suggested, 'source.lua');
          return '${directory.path}/another.lua';
        },
      );
      await login(tester);
      await page(tester, 1);
      Future<void> open() async {
        await tester.runAsync(() async {
          await tester.tap(action('Open File'));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
      }

      await open();
      final firstImport = c.activeDocumentId;
      expect(find.text('source'), findsOneWidget);
      file.writeAsStringSync('print("second")');
      await open();
      expect(c.documents, hasLength(3));
      expect(c.activeDocumentId, isNot(firstImport));
      expect(c.activeDocument.content, 'print("second")');
      expect(
        c.documents.firstWhere((d) => d.id == firstImport).content,
        'print("first")',
      );
      for (var i = 0; i < 2; i++) {
        await tester.tap(action('Save File'));
        await tester.pumpAndSettle();
      }
      expect(savePickers, 2);
      expect(c.savedPaths, hasLength(2));
      expect(c.savedBody, 'print("second")');
      expect(c.activeDocument.name, 'source.lua');
      await cleanup(tester, c);
    },
  );
}
