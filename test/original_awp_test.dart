import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_models.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/original_ports/awp_shell.dart';
import 'package:orion/original_ports/awp_controls.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/services/file_paths.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

class OriginalPortController extends OrionController {
  int opened = 0;
  String? savedBody;
  final List<String> savedPaths = [];
  @override
  Future<void> flushPersistence() async {}
  @override
  Future<EditorDocument?> openFile() async {
    opened++;
    return newDocument(name: 'disk.lua', content: 'print("disk")');
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

class OriginalPortAssets extends EditorAssetServer {
  @override
  Future<Uri> start() async =>
      Uri.parse('http://127.0.0.1:9988/editor/index.html');
  @override
  Future<void> close() async {}
}

class OriginalPortChannel extends MethodChannel {
  OriginalPortChannel() : super('orion/original-port-test');
  Future<dynamic> Function(MethodCall)? handler;
  Map<String, dynamic>? snapshot;
  Completer<Uint8List?>? previewGate;
  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall)? callback) {
    handler = callback;
  }

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic args]) async {
    if (method == 'capturePreview' && previewGate != null) {
      return await previewGate!.future as T?;
    }
    if (method == 'create') {
      await handler?.call(MethodCall('message', jsonEncode({'type': 'ready'})));
    }
    if (method == 'send') {
      final command = jsonDecode(args as String) as Map<String, dynamic>;
      if (command['type'] == 'sync') snapshot = command;
      if (command['type'] == 'flush') {
        final d = (snapshot!['documents'] as List).firstWhere(
          (d) => d['id'] == snapshot!['activeId'],
        );
        await handler?.call(
          MethodCall(
            'message',
            jsonEncode({
              'type': 'flush',
              'requestId': command['requestId'],
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

Future<void> loadOriginalPortFonts() async {
  for (final family in {
    'OriginalAwpUI': [
      'assets/original_awp/Inter-Regular.ttf',
      'assets/original_awp/Inter-Medium.ttf',
      'assets/original_awp/Inter-SemiBold.ttf',
      'assets/original_awp/Inter-Bold.ttf',
    ],
    'OriginalXenoUI': [
      'assets/original_xeno/NotoSans-Regular.ttf',
      'assets/original_xeno/NotoSans-SemiBold.ttf',
      'assets/original_xeno/NotoSans-Black.ttf',
    ],
    'SynapseXMono': ['assets/synapse_x/fonts/LiberationMono-Regular.ttf'],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final asset in family.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadOriginalPortFonts);
  Future<void> mount(
    WidgetTester tester,
    OriginalPortController c, {
    VoidCallback? back,
    MonacoEditorService? service,
    GlobalKey<AwpShellState>? key,
    ThemeData? theme,
    Future<String?> Function()? pickScriptPath,
    Future<String?> Function(String)? pickSavePath,
  }) async {
    tester.view.physicalSize = const Size(820, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final shellKey = key ?? GlobalKey<AwpShellState>();
    final pickerDirectory = Directory.systemTemp.createTempSync('awp-picker-');
    addTearDown(() => pickerDirectory.deleteSync(recursive: true));
    final pickerFile = File('${pickerDirectory.path}/disk.lua')
      ..writeAsStringSync('print("disk")');
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) =>
            UiScaleViewport(scale: c.uiScale, child: child!),
        home: AwpShell(
          key: shellKey,
          controller: c,
          nativeWindow: false,
          onBackToOrion: back ?? () {},
          editorService: service,
          pickScriptPath:
              pickScriptPath ??
              () async {
                c.opened++;
                return pickerFile.path;
              },
          pickSavePath:
              pickSavePath ?? (_) async => '${pickerDirectory.path}/saved.lua',
        ),
      ),
    );
    await tester.runAsync(() => shellKey.currentState!.refreshLocalFiles());
    await tester.pumpAndSettle();
  }

  Future<void> cleanup(WidgetTester tester, OriginalPortController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  testWidgets(
    'AWP keeps native input geometry under a compact Linux Material host',
    (tester) async {
      final c = OriginalPortController();
      await mount(
        tester,
        c,
        theme: ThemeData(
          platform: TargetPlatform.linux,
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: Colors.blue,
          ),
        ),
      );
      final editable = find.descendant(
        of: find.byKey(const ValueKey('awp-login-username')),
        matching: find.byType(EditableText),
      );
      final container = InputDecorator.containerOf(tester.element(editable));
      expect(container!.size, const Size(260, 32));
      await tester.tap(find.byKey(const ValueKey('awp-login')));
      await tester.pumpAndSettle();
      final search = tester.widget<TextField>(
        find.byKey(const ValueKey('awp-script-search')),
      );
      expect(search.decoration!.filled, false);
      expect(search.decoration!.focusedBorder, InputBorder.none);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'AWP starts with source fake login and retains source chrome geometry',
    (tester) async {
      final c = OriginalPortController();
      await mount(tester, c);
      expect(
        find.text('Enter any credentials, this is a fake login page'),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('awp-login'))),
        const Size(260, 34),
      );
      await tester.tap(find.byKey(const ValueKey('awp-login')));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter any credentials, this is a fake login page'),
        findsNothing,
      );
      expect(
        tester.getSize(find.byKey(ValueKey('awp-tab-${c.activeDocumentId}'))),
        const Size(150, 28),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('awp-console'))).height,
        130,
      );
      expect(tester.getRect(find.byKey(const ValueKey('code-editor'))).top, 69);
      expect(
        tester.getRect(find.byKey(const ValueKey('code-editor'))).bottom,
        389,
      );
      final executes = tester
          .widgetList<AwpButton>(
            find.byWidgetPredicate(
              (w) => w is AwpButton && w.label == 'Execute',
            ),
          )
          .toList();
      expect(executes.length, 2);
      expect(executes.every((b) => b.onPressed == null), true);
      expect(find.byKey(const ValueKey('awp-back-to-orion')), findsNothing);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'AWP tabs, clear/open/save and console collapse use actual shared workspace',
    (tester) async {
      final c = OriginalPortController();
      await mount(tester, c);
      await tester.tap(find.byKey(const ValueKey('awp-login')));
      await tester.pumpAndSettle();
      c.updateDocumentContent(c.activeDocumentId, 'print("draft")');
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(c.savedBody, 'print("draft")');
      await tester.runAsync(() async {
        await tester.tap(find.text('Open'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(c.opened, 1);
      expect(c.activeDocument.name, 'disk.lua');
      await tester.tap(find.byKey(const ValueKey('awp-new-tab')));
      await tester.pumpAndSettle();
      expect(c.documents.length, 3);
      await tester.enterText(
        find.byKey(const ValueKey('code-editor')),
        'print("new")',
      );
      await tester.pump();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(c.activeDocument.content, '');
      await tester.tap(find.byTooltip('Collapse console'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('awp-console'))).height,
        33,
      );
      expect(
        c.getInterfacePreferences(InterfacePreset.awp)['consoleOpen'],
        false,
      );
      expect(find.byKey(const ValueKey('awp-console-resize')), findsNothing);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'AWP Back to Orion lives in settings, does not lose draft or tab selection',
    (tester) async {
      final c = OriginalPortController();
      var returned = 0;
      await mount(tester, c, back: () => returned++);
      await tester.tap(find.byKey(const ValueKey('awp-login')));
      await tester.pumpAndSettle();
      final id = c.activeDocumentId;
      c.updateDocumentContent(id, 'print("unsaved")');
      await tester.pump();
      await tester.tap(find.text('Scripting').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('awp-menu-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('awp-back-to-orion')), findsOneWidget);
      expect(find.text('Auto Inject: Off'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('awp-back-to-orion')));
      await tester.pumpAndSettle();
      expect(returned, 1);
      expect(c.activeDocumentId, id);
      expect(c.activeDocument.content, 'print("unsaved")');
      expect(c.activeDocument.isDirty, true);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'AWP source native snapshot and login visibility use root Monaco',
    (tester) async {
      final c = OriginalPortController();
      final channel = OriginalPortChannel();
      final service = MonacoEditorService(
        channel: channel,
        server: OriginalPortAssets(),
        onChange: c.updateDocumentContent,
        onShortcut: (_) {},
      );
      await mount(tester, c, service: service);
      expect(channel.snapshot?['options']['shell'], 'originalAwp');
      expect(channel.snapshot?['options']['fontSize'], 13);
      expect(channel.snapshot?['options']['background'], '#191818');
      await tester.tap(find.byKey(const ValueKey('awp-login')));
      await tester.pumpAndSettle();
      c.updateDocumentContent(c.activeDocumentId, 'print("native draft")');
      await tester.pumpAndSettle();
      expect(
        (channel.snapshot?['documents'] as List).last['content'],
        'print("native draft")',
      );
      await cleanup(tester, c);
      service.dispose();
    },
  );

  for (final scale in [.8, 1.0, 1.25]) {
    testWidgets('AWP main/settings stay usable at GUI scale $scale', (
      tester,
    ) async {
      final c = OriginalPortController()..setUiScale(scale);
      await mount(tester, c);
      await tester.tap(find.byKey(const ValueKey('awp-login')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Scripting').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('awp-menu-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('awp-back-to-orion')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    });
  }

  testWidgets(
    'AWP local workspace lists real files and opens one into shared editor',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('orion-awp-test-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/local-script.lua');
      file.writeAsStringSync('print("local disk")');
      final c = OriginalPortController()
        ..setInterfacePreference(
          InterfacePreset.awp,
          'scriptsDirectory',
          directory.path,
        );
      await mount(tester, c);
      await tester.tap(find.byKey(const ValueKey('awp-login')));
      await tester.pumpAndSettle();
      expect(find.text('local-script.lua'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('local-script.lua'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(c.activeDocument.content, 'print("local disk")');
      expect(FilePaths.same(c.activeDocument.filePath!, file.path), isTrue);
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'AWP source workspace filters script types and repeated imports create fresh tabs',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('awp-imports-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final script = File('${directory.path}/loaded.LUA')
        ..writeAsStringSync('print("first")');
      File('${directory.path}/notes.txt').writeAsStringSync('text');
      File('${directory.path}/ignored.json').writeAsStringSync('{}');
      File('${directory.path}/ignored.md').writeAsStringSync('# text');
      final c = OriginalPortController()
        ..setInterfacePreference(
          InterfacePreset.awp,
          'scriptsDirectory',
          directory.path,
        );
      await mount(tester, c);
      await tester.tap(find.byKey(const ValueKey('awp-login')));
      await tester.pumpAndSettle();
      expect(find.text('loaded.LUA'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('ignored.json'), findsNothing);
      expect(find.text('ignored.md'), findsNothing);
      Future<void> import() async {
        await tester.runAsync(() async {
          await tester.tap(find.text('loaded.LUA'));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
      }

      await import();
      final first = c.activeDocumentId;
      expect(find.text('loaded'), findsOneWidget);
      script.writeAsStringSync('print("second")');
      await import();
      expect(c.documents, hasLength(3));
      expect(c.activeDocumentId, isNot(first));
      expect(c.activeDocument.content, 'print("second")');
      expect(
        c.documents.firstWhere((d) => d.id == first).content,
        'print("first")',
      );
      expect(FilePaths.same(c.activeDocument.filePath!, script.path), isTrue);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'AWP tab rename commits on focus loss, cancels on Escape, and active close chooses previous tab',
    (tester) async {
      final c = OriginalPortController();
      final first = c.activeDocumentId;
      final middle = c.newDocument(name: 'Middle');
      final last = c.newDocument(name: 'Last');
      c.selectDocument(middle.id);
      await mount(tester, c);
      await tester.tap(find.byKey(const ValueKey('awp-login')));
      await tester.pumpAndSettle();
      Future<void> rename(String title) async {
        await tester.tap(find.text(title));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }

      await rename('Middle');
      expect(find.byType(TextFormField), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '  Changed  ');
      await tester.tap(find.byKey(const ValueKey('awp-script-search')));
      await tester.pumpAndSettle();
      expect(c.documents.firstWhere((d) => d.id == middle.id).name, 'Changed');
      await rename('Changed');
      await tester.enterText(find.byType(TextFormField), 'Cancelled');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.documents.firstWhere((d) => d.id == middle.id).name, 'Changed');
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('awp-tab-${middle.id}')),
          matching: find.byTooltip('Close tab'),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.activeDocumentId, first);
      expect(c.documents.last.id, last.id);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'AWP clearing its console preserves global activity and only hides existing output',
    (tester) async {
      final c = OriginalPortController()
        ..executeSource('print("one")', name: 'first.lua');
      await mount(tester, c);
      await tester.tap(find.byKey(const ValueKey('awp-login')));
      await tester.pumpAndSettle();
      expect(find.textContaining('run first.lua.'), findsOneWidget);
      final count = c.activities.length;
      await tester.tap(find.byTooltip('Clear console'));
      await tester.pumpAndSettle();
      expect(c.activities, hasLength(count));
      expect(find.textContaining('run first.lua.'), findsNothing);
      c.executeSource('print("two")', name: 'second.lua');
      await tester.pumpAndSettle();
      expect(find.textContaining('run second.lua.'), findsOneWidget);
      expect(find.textContaining('run first.lua.'), findsNothing);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'AWP source Save asks every time even when the active file already has a path',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('awp-save-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/existing.lua')
        ..writeAsStringSync('print("saved")');
      final c = OriginalPortController();
      await tester.runAsync(() => c.importDocumentFromPath(file.path));
      var pickerCount = 0;
      await mount(
        tester,
        c,
        pickSavePath: (name) async {
          pickerCount++;
          expect(name, 'existing.lua');
          return '${directory.path}/chosen.lua';
        },
      );
      await tester.tap(find.byKey(const ValueKey('awp-login')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(() async {
          await tester.tap(find.text('Save'));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
      }
      expect(pickerCount, 2);
      expect(c.savedPaths, [
        '${directory.path}/chosen.lua',
        '${directory.path}/chosen.lua',
      ]);
      expect(c.savedBody, 'print("saved")');
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'AWP waits for the native code frame before opening its page menu and reveals it on dismiss',
    (tester) async {
      final c = OriginalPortController();
      final channel = OriginalPortChannel()
        ..previewGate = Completer<Uint8List?>();
      final service = MonacoEditorService(
        channel: channel,
        server: OriginalPortAssets(),
        onChange: c.updateDocumentContent,
        onShortcut: (_) {},
      );
      final frame = (await rootBundle.load(
        'assets/original_xeno/open.png',
      )).buffer.asUint8List();
      await mount(tester, c, service: service);
      await tester.tap(find.byKey(const ValueKey('awp-login')));
      await tester.pumpAndSettle();
      expect(service.visible, true);
      await tester.tap(find.text('Scripting').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('awp-menu-settings')), findsNothing);
      expect(service.visible, true);
      channel.previewGate!.complete(frame);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('awp-menu-settings')), findsOneWidget);
      expect(service.visible, false);
      expect(
        find.byKey(const ValueKey('monaco-frozen-preview')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('awp-menu-scripting')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('awp-menu-settings')), findsNothing);
      expect(find.byKey(const ValueKey('monaco-frozen-preview')), findsNothing);
      expect(service.visible, true);
      await cleanup(tester, c);
      service.dispose();
    },
  );
}
