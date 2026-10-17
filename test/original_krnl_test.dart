import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/companion_window.dart';
import 'package:orion/models/orion_models.dart';
import 'package:orion/original_ports/krnl_controls.dart';
import 'package:orion/original_ports/krnl_shell.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/widgets/monaco_editor.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

class _Controller extends OrionController {
  int opened = 0;
  String? saved, persisted;
  @override
  Future<void> flushPersistence() async {
    persisted = activeDocument.content;
  }

  @override
  Future<EditorDocument?> openFile() async {
    opened++;
    return newDocument(name: 'disk.lua', content: 'print("disk")');
  }

  @override
  Future<bool> saveDocument([String? id]) async {
    saved = activeDocument.content;
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

class _Windows implements CompanionWindowHost {
  _Windows({this.kind});
  @override
  final CompanionWindowKind? kind;
  @override
  bool get isChildWindow => kind != null;
  @override
  String? get documentId => null;
  final opened = <CompanionWindowKind>[];
  final opacities = <double>[];
  int closed = 0, closedAll = 0, returned = 0;
  VoidCallback? onCloseAll;
  bool? ownerTopMost;
  @override
  Future<void> open(CompanionWindowKind kind, {String? documentId}) async {
    opened.add(kind);
  }

  @override
  Future<void> close() async => closed++;
  @override
  Future<void> closeAll() async {
    closedAll++;
    onCloseAll?.call();
  }

  @override
  Future<void> returnToOrion() async => returned++;
  @override
  Future<void> focusMain() async {}
  @override
  Future<void> updateOwnerWindow({
    bool? alwaysOnTop,
    bool? resizable,
    double? opacity,
  }) async {
    if (alwaysOnTop != null) ownerTopMost = alwaysOnTop;
    if (opacity != null) opacities.add(opacity);
  }
}

class _Channel extends MethodChannel {
  _Channel() : super('orion/original-krnl-test');
  Future<dynamic> Function(MethodCall)? handler;
  Map<String, dynamic>? snapshot;
  final calls = <MethodCall>[];
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      ('OriginalSegoeUI', 'assets/synapse_x/fonts/Cantarell-Regular.otf'),
      ('OriginalConsolas', 'assets/synapse_x/fonts/LiberationMono-Regular.ttf'),
      ('OriginalSans', 'assets/original_fonts/LiberationSans-Regular.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  Future<void> mount(
    WidgetTester tester,
    _Controller c, {
    MonacoEditorService? service,
    Directory? directory,
    VoidCallback? back,
    Size size = const Size(679, 345),
    GlobalKey<KrnlShellState>? key,
    bool reduced = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    c.setReducedMotion(reduced);
    await tester.pumpWidget(
      MaterialApp(
        builder: (ctx, child) =>
            UiScaleViewport(scale: c.uiScale, child: child!),
        home: KrnlShell(
          key: key,
          controller: c,
          nativeWindow: false,
          onBackToOrion: back ?? () {},
          editorService: service,
          scriptDirectory: directory,
        ),
      ),
    );
    if (reduced) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> cleanup(WidgetTester tester, _Controller c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  testWidgets(
    'KRNL source geometry, disconnected actions and native editor skin',
    (tester) async {
      final c = _Controller(), channel = _Channel();
      final service = MonacoEditorService(
        channel: channel,
        server: _Assets(),
        onChange: c.updateDocumentContent,
        onShortcut: (_) {},
      );
      await mount(tester, c, service: service);
      expect(
        tester.getRect(find.byKey(const ValueKey('krnl-tabs-container'))),
        const Rect.fromLTWH(4, 59, 545, 254),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('krnl-script-tree'))),
        const Rect.fromLTWH(554, 59, 121, 254),
      );
      expect(
        tester.getRect(find.byType(MonacoEditor)),
        const Rect.fromLTWH(8, 83, 537, 227),
      );
      for (final action in [
        (0, 4.0),
        (1, 107.0),
        (2, 210.0),
        (3, 313.0),
        (4, 416.0),
      ]) {
        expect(
          tester.getRect(find.byKey(ValueKey('krnl-action-${action.$1}'))),
          Rect.fromLTWH(action.$2, 316, 100, 25),
        );
      }
      expect(
        tester
            .widget<KrnlButton>(find.byKey(const ValueKey('krnl-action-0')))
            .onPressed,
        isNull,
      );
      final options = channel.snapshot!['options'] as Map;
      expect(options['shell'], 'originalKrnl');
      expect(options['fontSize'], closeTo(13.33333, .0001));
      expect(options['background'], '#282828');
      expect(options['lineNumbers'], true);
      expect(options['animateReveal'], false);
      await cleanup(tester, c);
      expect(service.ready, true);
      service.dispose();
    },
  );
  testWidgets(
    'files clear tabs and compact source settings preserve workspace',
    (tester) async {
      final c = _Controller();
      var backs = 0;
      await mount(tester, c, back: () => backs++);
      expect(find.text('Back to Orion'), findsNothing);
      await tester.tap(find.text('OPEN FILE'));
      await tester.pumpAndSettle();
      expect(c.opened, 1);
      await tester.enterText(
        find.byKey(const ValueKey('code-editor')),
        'print("unsaved")',
      );
      await tester.tap(find.text('SAVE FILE'));
      await tester.pumpAndSettle();
      expect(c.saved, 'print("unsaved")');
      await tester.tap(find.text('CLEAR'));
      await tester.pumpAndSettle();
      expect(c.activeDocument.content, '');
      await tester.tap(find.byKey(const ValueKey('krnl-add-tab')));
      await tester.pumpAndSettle();
      expect(c.documents.length, 3);
      expect(c.activeDocument.name, 'Script 2.lua');
      await tester.enterText(
        find.byKey(const ValueKey('code-editor')),
        'print("carry over")',
      );
      await tester.tap(find.text('OPTIONS'));
      await tester.pumpAndSettle();
      expect(find.text('Back to Orion'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('krnl-top-most')));
      await tester.pumpAndSettle();
      expect(
        c.getInterfacePreferences(InterfacePreset.krnl)['alwaysOnTop'],
        true,
      );
      await tester.tap(find.byKey(const ValueKey('krnl-opacity-fade')));
      await tester.pumpAndSettle();
      expect(
        c.getInterfacePreferences(InterfacePreset.krnl)['opacityFade'],
        true,
      );
      await tester.tap(find.text('Back to Orion'));
      await tester.pumpAndSettle();
      expect(backs, 1);
      expect(c.activeDocument.content, 'print("carry over")');
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'source tabs align left and swap during dragging before release',
    (tester) async {
      final c = _Controller();
      c.renameDocument(c.activeDocumentId, 'one.lua');
      final first = c.activeDocumentId;
      final second = c.newDocument(name: 'two.lua', content: 'second').id;
      final third = c.newDocument(name: 'three.lua', content: 'third').id;
      c.selectDocument(first);
      await mount(tester, c);
      Finder tab(String id) => find.byKey(ValueKey('krnl-tab-$id'));
      final firstBounds = tester.getRect(tab(first));
      expect(firstBounds.left, 6);
      expect(firstBounds.height, 20);
      expect(tester.getRect(find.text('one.lua')).left, firstBounds.left + 2);
      expect(
        tester.getSize(find.byKey(const ValueKey('krnl-add-tab'))).width,
        54,
      );
      expect(find.byTooltip('Close tab'), findsNothing);
      final gesture = await tester.startGesture(tester.getCenter(tab(first)));
      await gesture.moveTo(tester.getCenter(tab(second)));
      await tester.pump();
      expect(c.documents.map((d) => d.id), [second, first, third]);
      expect(c.activeDocumentId, first);
      await gesture.moveTo(tester.getCenter(tab(third)));
      await tester.pump();
      expect(c.documents.map((d) => d.id), [second, third, first]);
      expect(c.documents.singleWhere((d) => d.id == third).content, 'third');
      await gesture.up();
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'source tab context selects first and closing selects left neighbor',
    (tester) async {
      final c = _Controller();
      c.renameDocument(c.activeDocumentId, 'one.lua');
      final first = c.activeDocumentId;
      final second = c.newDocument(name: 'two.lua').id;
      final third = c.newDocument(name: 'three.lua').id;
      await mount(tester, c);
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('krnl-tab-$second'))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await pointer.up();
      await tester.pumpAndSettle();
      expect(c.activeDocumentId, second);
      expect(find.byType(PopupMenuDivider), findsOneWidget);
      final surface = tester.widgetList<Material>(find.byType(Material));
      expect(surface.any((m) => m.color == const Color(0xfff0f0f0)), true);
      await tester.tap(find.text('Close Tab'));
      await tester.pumpAndSettle();
      expect(c.documents.map((d) => d.id), [first, third]);
      expect(c.activeDocumentId, first);
      await tester.tap(find.byKey(const ValueKey('krnl-add-tab')));
      await tester.pumpAndSettle();
      expect(c.activeDocument.name, 'Script 4.lua');
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'overflow arrows expose hidden source tabs and preserve active editor',
    (tester) async {
      final c = _Controller();
      c.renameDocument(c.activeDocumentId, 'first-script.lua');
      for (var index = 2; index <= 12; index++) {
        c.newDocument(name: 'source-script-$index.lua', content: '$index');
      }
      final last = c.activeDocumentId;
      c.selectDocument(c.documents.first.id);
      await mount(tester, c);
      final right = find.byKey(const ValueKey('krnl-tabs-scroll-right'));
      expect(right, findsOneWidget);
      final start = tester.getRect(find.byKey(ValueKey('krnl-tab-$last'))).left;
      await tester.tap(right);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(ValueKey('krnl-tab-$last'))).left,
        lessThan(start),
      );
      final key = find.byKey(const ValueKey('krnl-add-tab'));
      for (var index = 0; index < 14; index++) {
        await tester.tap(right);
        await tester.pump();
      }
      await tester.tap(key);
      await tester.pumpAndSettle();
      expect(c.documents.length, 13);
      expect(c.activeDocument.name, 'Script 13.lua');
      expect(c.documents.singleWhere((d) => d.id == last).content, '12');
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'native options open separately while the main editor stays active',
    (tester) async {
      final c = _Controller(), windows = _Windows(), channel = _Channel();
      c.companionWindows = windows;
      final service = MonacoEditorService(
        channel: channel,
        server: _Assets(),
        onChange: c.updateDocumentContent,
        onShortcut: (_) {},
      );
      await mount(tester, c, service: service);
      final editor = tester.getRect(find.byType(MonacoEditor));
      await tester.tap(find.text('OPTIONS'));
      await tester.pumpAndSettle();
      expect(windows.opened, [CompanionWindowKind.krnlOptions]);
      expect(tester.getRect(find.byType(MonacoEditor)), editor);
      expect(
        tester.widget<MonacoEditor>(find.byType(MonacoEditor)).active,
        true,
      );
      expect(find.text('Back to Orion'), findsNothing);
      await cleanup(tester, c);
      service.dispose();
    },
  );
  testWidgets('options child has no editor and routes controls to its owner', (
    tester,
  ) async {
    final c = _Controller(),
        windows = _Windows(kind: CompanionWindowKind.krnlOptions);
    c.companionWindows = windows;
    final channel = _Channel();
    final service = MonacoEditorService(
      channel: channel,
      server: _Assets(),
      onChange: c.updateDocumentContent,
      onShortcut: (_) {},
    );
    await mount(tester, c, service: service, size: const Size(248, 153));
    expect(find.byType(MonacoEditor), findsNothing);
    expect(channel.calls, isEmpty);
    expect(
      tester.getRect(find.byKey(const ValueKey('krnl-top-most'))),
      const Rect.fromLTWH(187, 52, 54, 21),
    );
    await tester.tap(find.byKey(const ValueKey('krnl-top-most')));
    await tester.pumpAndSettle();
    expect(windows.ownerTopMost, true);
    await tester.tap(find.byTooltip('Close settings'));
    await tester.pumpAndSettle();
    expect(windows.closed, 1);
    await tester.tap(find.text('Back to Orion'));
    await tester.pumpAndSettle();
    expect(windows.returned, 1);
    expect(windows.closedAll, 0);
    await cleanup(tester, c);
    service.dispose();
  });
  testWidgets('closing the main window persists edits flushed by companions', (
    tester,
  ) async {
    final c = _Controller(), windows = _Windows();
    c.companionWindows = windows;
    windows.onCloseAll = () =>
        c.updateDocumentContent(c.activeDocumentId, 'final companion draft');
    final key = GlobalKey<KrnlShellState>();
    await mount(tester, c, key: key);
    key.currentState!.onWindowClose();
    await tester.pumpAndSettle();
    expect(windows.closedAll, 1);
    expect(c.persisted, 'final companion draft');
    await cleanup(tester, c);
  });
  testWidgets('source Options uses its 248 by 153 control bounds', (
    tester,
  ) async {
    final c = _Controller();
    final key = GlobalKey<KrnlShellState>();
    await mount(tester, c, key: key, size: const Size(248, 153));
    await tester.tap(find.text('OPTIONS'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('krnl-top-most'))),
      const Rect.fromLTWH(187, 52, 54, 21),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('krnl-opacity-fade'))),
      const Rect.fromLTWH(187, 81, 54, 21),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('krnl-back-to-orion'))),
      const Rect.fromLTWH(10, 118, 130, 23),
    );
    key.currentState!.handleEditorShortcut('show-editor');
    await tester.pumpAndSettle();
    expect(find.text('OPEN FILE'), findsOneWidget);
    await cleanup(tester, c);
  });
  testWidgets('source accent pulses rather than inventing an intro', (
    tester,
  ) async {
    final c = _Controller();
    await mount(tester, c, reduced: false);
    final initial = tester
        .widget<ColoredBox>(find.byKey(const ValueKey('krnl-blue-accent')))
        .color;
    await tester.pump(const Duration(milliseconds: 210));
    final midpoint = tester
        .widget<ColoredBox>(find.byKey(const ValueKey('krnl-blue-accent')))
        .color;
    expect(initial, const Color(0xff1e90ff));
    expect(midpoint.r, closeTo(30 / 255, .001));
    expect(midpoint.g, lessThan(initial.g));
    expect(midpoint.b, lessThan(initial.b));
    await cleanup(tester, c);
  });
  testWidgets(
    'local folder tree opens exact disk content without script execution',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('orion-krnl-test-'),
      ))!;
      addTearDown(
        () => tester.runAsync(() => directory.delete(recursive: true)),
      );
      await tester.runAsync(() async {
        final nested = await Directory('${directory.path}/Examples').create();
        await File(
          '${nested.path}/exact.lua',
        ).writeAsString('print("exact")\n-- local file');
      });
      final c = _Controller();
      final key = GlobalKey<KrnlShellState>();
      await mount(tester, c, directory: directory, key: key);
      await tester.runAsync(() => key.currentState!.reloadScripts());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Examples'));
      await tester.pumpAndSettle();
      expect(find.text('exact.lua'), findsOneWidget);
      await tester.tap(find.text('exact.lua'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        await tester.tap(find.text('exact.lua'));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pumpAndSettle();
      expect(c.activeDocument.name, 'exact.lua');
      expect(c.activeDocument.content, 'print("exact")\n-- local file');
      expect(c.activities.any((a) => a.kind == ActivityKind.execution), false);
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'source pages fit at 80 and 125 percent without clipped controls',
    (tester) async {
      for (final scale in [.8, 1.25]) {
        final c = _Controller()..setUiScale(scale);
        await mount(tester, c);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('OPTIONS'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Back to Orion'), findsOneWidget);
        await cleanup(tester, c);
      }
    },
  );
}
