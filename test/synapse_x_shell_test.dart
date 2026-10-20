import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_models.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/synapse_x/synapse_x_shell.dart';
import 'package:orion/synapse_x/synapse_x_theme.dart';
import 'package:orion/widgets/monaco_editor.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

class _Controller extends OrionController {
  _Controller() : super(useMacSploit: false);

  int opened = 0;
  String? savedBody, executedBody, executedName;
  @override
  Future<void> flushPersistence() async {}
  @override
  Future<EditorDocument?> openFile() async {
    opened++;
    return newDocument(name: 'opened.lua', content: 'print("disk")');
  }

  @override
  Future<bool> saveDocument([String? id]) async {
    savedBody = activeDocument.content;
    return true;
  }

  @override
  void execute({String? source, String? name}) {
    executedBody = source ?? activeDocument.content;
    executedName = name ?? activeDocument.name;
    super.execute(source: source, name: name);
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
  _Channel() : super('orion/synapse-x-test');
  Future<dynamic> Function(MethodCall)? handler;
  final calls = <MethodCall>[];
  Map<String, dynamic>? snapshot;
  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall)? callback) {
    handler = callback;
  }

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic args]) async {
    calls.add(MethodCall(method, args));
    if (method == 'create') {
      await handler?.call(MethodCall('message', jsonEncode({'type': 'ready'})));
    }
    if (method == 'send') {
      final cmd = jsonDecode(args as String) as Map<String, dynamic>;
      if (cmd['type'] == 'sync') snapshot = cmd;
      if (cmd['type'] == 'flush') {
        final d = (snapshot!['documents'] as List).firstWhere(
          (d) => d['id'] == snapshot!['activeId'],
        );
        await handler?.call(
          MethodCall(
            'message',
            jsonEncode({
              'type': 'flush',
              'requestId': cmd['requestId'],
              'id': d['id'],
              'content': d['content'],
            }),
          ),
        );
      }
    }
    return null;
  }
}

Widget _fixture(
  _Controller c, {
  MonacoEditorService? service,
  bool bridge = false,
  bool intro = false,
  VoidCallback? complete,
  GlobalKey<SynapseXShellState>? key,
  VoidCallback? back,
}) => MaterialApp(
  builder: (context, child) => UiScaleViewport(scale: c.uiScale, child: child!),
  home: SynapseXShell(
    key: key,
    controller: c,
    nativeWindow: false,
    onBackToOrion: back ?? () {},
    editorService: service,
    bridgeReady: bridge,
    playIntro: intro,
    onIntroCompleted: complete,
  ),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      ('SynapseInter', 'assets/synapse_v3/fonts/Inter-Regular.ttf'),
      ('SynapseXMono', 'assets/synapse_x/fonts/LiberationMono-Regular.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  Future<void> mount(
    WidgetTester tester,
    _Controller c, {
    MonacoEditorService? service,
    bool bridge = false,
    Size size = const Size(801, 355),
    GlobalKey<SynapseXShellState>? key,
    VoidCallback? back,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _fixture(c, service: service, bridge: bridge, key: key, back: back),
    );
    await tester.pumpAndSettle();
  }

  Future<void> cleanup(WidgetTester tester, _Controller c) async {
    await tester.pumpWidget(const SizedBox());
    await c.flushPersistence();
    c.dispose();
  }

  testWidgets(
    'X has source action geometry, disconnected gating, and real Monaco snapshot',
    (tester) async {
      final c = _Controller();
      final channel = _Channel();
      final service = MonacoEditorService(
        channel: channel,
        server: _Assets(),
        onChange: c.updateDocumentContent,
        onShortcut: (_) {},
      );
      await mount(tester, c, service: service);
      for (final label in [
        'Execute',
        'Clear',
        'Open File',
        'Execute File',
        'Save File',
        'Options',
        'Attach',
        'Script Hub',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      final box = tester.getRect(find.byType(MonacoEditor));
      expect(box.left, 10);
      expect(box.top, closeTo(52.6, .01));
      expect(box.width, 658);
      expect(box.bottom, 309);
      final execute = find.ancestor(
        of: find.text('Execute'),
        matching: find.byType(TextButton),
      );
      expect(tester.widget<TextButton>(execute).onPressed, isNull);
      expect(
        tester.getRect(find.byKey(const ValueKey('x-action-0'))),
        const Rect.fromLTWH(10, 315, 91, 33),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('x-action-6'))).left,
        608,
      );
      final options = channel.snapshot!['options'] as Map;
      expect(options['shell'], 'synapseX');
      expect(options['editorThemeId'], 'net-theme-dark');
      expect(options['fontSize'], 14);
      expect(options['animateReveal'], false);
      expect(
        (channel.calls.lastWhere((call) => call.method == 'setBounds').arguments
            as Map)['reducedMotion'],
        true,
      );
      expect(options['reducedMotion'], false);
      expect(service.visible, isTrue);
      await cleanup(tester, c);
      expect(service.ready, isTrue);
      service.dispose();
    },
  );
  testWidgets('Hub keeps original button, row and preview geometry', (
    tester,
  ) async {
    final c = _Controller();
    await mount(tester, c, size: const Size(612, 384));
    await tester.tap(find.text('Script Hub'));
    await tester.pumpAndSettle();
    final tab = find.ancestor(
      of: find.text('Synapse Hub'),
      matching: find.byType(TextButton),
    );
    expect(tester.getRect(tab), const Rect.fromLTWH(8, 38, 100, 33));
    final row = find.ancestor(
      of: find.text('Dark Dex'),
      matching: find.byType(TextButton),
    );
    expect(tester.getRect(row).top, 45);
    expect(tester.getRect(row).height, closeTo(27.125, .25));
    final run = find.ancestor(
      of: find.text('Run Script'),
      matching: find.byType(TextButton),
    );
    expect(tester.getRect(run).top, 343);
    expect(tester.getRect(run).height, 33);
    await cleanup(tester, c);
  });

  testWidgets(
    'source controls open save clear add tab and Options preferences work',
    (tester) async {
      final c = _Controller();
      var backed = false;
      await mount(tester, c, back: () => backed = true);
      expect(find.text('Back to Orion'), findsNothing);
      await tester.tap(find.text('Open File'));
      await tester.pumpAndSettle();
      expect(c.opened, 1);
      expect(c.activeDocument.content, 'print("disk")');
      await tester.tap(find.text('Save File'));
      await tester.pumpAndSettle();
      expect(c.savedBody, 'print("disk")');
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(c.activeDocument.content, isEmpty);
      await tester.tap(find.byTooltip('Add script tab'));
      await tester.pumpAndSettle();
      expect(c.documents.length, 3);
      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
      expect(find.text('Synapse X - Options'), findsOneWidget);
      await tester.tap(find.text('Top Most'));
      await tester.pumpAndSettle();
      expect(
        c.getInterfacePreferences(InterfacePreset.synapseX)['alwaysOnTop'],
        true,
      );
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('synapse-theme-studio')),
        findsOneWidget,
      );
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
      expect(find.text('Execute File'), findsOneWidget);
      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
      final back = find.byKey(const ValueKey('x-back-to-orion'));
      await tester.ensureVisible(back);
      await tester.pumpAndSettle();
      expect(find.text('Back to Orion'), findsOneWidget);
      await tester.tap(back);
      expect(backed, isTrue);
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'Execute File sends exact selected body without changing active documents',
    (tester) async {
      final file = (await tester.runAsync(
        () => File(
          '${Directory.systemTemp.path}/orion-x-execute-${DateTime.now().microsecondsSinceEpoch}.lua',
        ).writeAsString('print("file")\n-- exact\r\n'),
      ))!;
      const selector = MethodChannel('plugins.flutter.io/file_selector');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        selector,
        (call) async => call.method == 'openFile' ? <String>[file.path] : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          selector,
          null,
        ),
      );
      addTearDown(() => tester.runAsync(file.delete));
      final c = _Controller();
      await mount(tester, c, bridge: true);
      final id = c.activeDocumentId,
          body = c.activeDocument.content,
          count = c.documents.length;
      await tester.runAsync(() async {
        await tester.tap(find.text('Execute File'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(c.executedBody, 'print("file")\n-- exact\r\n');
      expect(c.executedName, file.uri.pathSegments.last);
      expect(c.activeDocumentId, id);
      expect(c.activeDocument.content, body);
      expect(c.documents.length, count);
      expect(c.activities.first.title, 'No clients connected');
      await cleanup(tester, c);
    },
  );
  testWidgets('source loader advances then fades into the main shell once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(418, 117);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = _Controller();
    var completed = 0;
    await tester.pumpWidget(
      _fixture(c, intro: true, complete: () => completed++),
    );
    await tester.pump();
    expect(find.text('Initializing...'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(completed, 1);
    expect(find.text('Execute File'), findsOneWidget);
    await cleanup(tester, c);
  });
  testWidgets('all source pages remain usable at 80 and 125 percent', (
    tester,
  ) async {
    final c = _Controller();
    await mount(tester, c);
    final key = GlobalKey<SynapseXShellState>();
    for (final scale in [.8, 1.25]) {
      c.setUiScale(scale);
      await tester.pumpWidget(_fixture(c, key: key));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Script Hub'));
      await tester.pumpAndSettle();
      expect(find.text('Dark Dex'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
      key.currentState!.handleEditorShortcut('console');
      await tester.pumpAndSettle();
      expect(find.text('Synapse X - F9 Console'), findsOneWidget);
      expect(tester.takeException(), isNull);
      key.currentState!.handleEditorShortcut('show-editor');
      await tester.pumpAndSettle();
    }
    await cleanup(tester, c);
  });
  test(
    'opacity owners compose, survive replacement, and never change source or visibility',
    () async {
      final channel = _Channel();
      final service = MonacoEditorService(
        channel: channel,
        server: _Assets(),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      service.setOpacity(.25, owner: 'old');
      service.setOpacity(.5, owner: 'new');
      await service.synchronize({
        'documents': [
          {'id': 'a', 'name': 'a.lua', 'content': 'print("exact")'},
        ],
        'activeId': 'a',
        'options': {},
      });
      await service.initialize();
      await service.setBounds(x: 10, y: 20, width: 600, height: 256);
      expect(
        channel.calls
            .lastWhere((call) => call.method == 'setOpacity')
            .arguments,
        .125,
      );
      service.setOpacity(1, owner: 'old');
      await Future<void>.delayed(Duration.zero);
      expect(
        channel.calls
            .lastWhere((call) => call.method == 'setOpacity')
            .arguments,
        .5,
      );
      expect(service.visible, true);
      expect(
        (channel.snapshot!['documents'] as List).single['content'],
        'print("exact")',
      );
      service.setObscured(true, owner: 'dialog');
      expect((channel.calls.last.arguments as Map)['visible'], false);
      service.setOpacity(1, owner: 'new');
      await Future<void>.delayed(Duration.zero);
      expect(
        channel.calls
            .lastWhere((call) => call.method == 'setOpacity')
            .arguments,
        1,
      );
      service.setOpacity(double.nan);
      service.setOpacity(double.infinity);
      expect(service.visible, false);
      service.dispose();
    },
  );
  test(
    'source theme JSON restores omitted defaults and transparent borders atomically',
    () {
      final parsed = SynapseXTheme.decodeColors({
        'windowBg': '#181818',
        'buttonBorder': 'transparent',
      });
      expect(parsed['windowBg'], 0xff181818);
      expect(parsed['panelBg'], 0xff3c3c3c);
      expect(parsed['buttonBorder'], 0);
      expect(
        SynapseXTheme.decodeColors({
          'theme': {'text': '#EEEEEE'},
        })['text'],
        0xffeeeeee,
      );
      for (final malformed in [
        null,
        [],
        {'unknown': '#ffffff'},
        {'editorBg': 'red'},
        {'windowBg': 0xff333333},
      ]) {
        expect(
          () => SynapseXTheme.decodeColors(malformed),
          throwsFormatException,
        );
      }
    },
  );
}
