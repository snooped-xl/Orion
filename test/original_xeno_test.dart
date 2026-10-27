import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/companion_window.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/original_ports/xeno_shell.dart';
import 'package:orion/original_ports/xeno_controls.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

import 'original_awp_test.dart'
    show
        OriginalPortController,
        OriginalPortChannel,
        OriginalPortAssets,
        loadOriginalPortFonts;

class XenoTestWindows implements CompanionWindowHost {
  XenoTestWindows({this.kind});
  @override
  final CompanionWindowKind? kind;
  @override
  bool get isChildWindow => kind != null;
  @override
  String? get documentId => null;
  final opened = <CompanionWindowKind>[];
  int closed = 0, returned = 0, allClosed = 0;
  @override
  Future<void> open(CompanionWindowKind kind, {String? documentId}) async =>
      opened.add(kind);
  @override
  Future<void> close() async => closed++;
  @override
  Future<void> closeAll() async => allClosed++;
  @override
  Future<void> returnToOrion() async => returned++;
  @override
  Future<void> focusMain() async {}
  @override
  Future<void> updateOwnerWindow({
    bool? alwaysOnTop,
    bool? resizable,
    double? opacity,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadOriginalPortFonts);
  Future<void> mount(
    WidgetTester tester,
    OriginalPortController c, {
    VoidCallback? back,
    MonacoEditorService? service,
    GlobalKey<XenoShellState>? key,
    Future<String?> Function()? pickScriptPath,
    Future<String?> Function(String)? pickSavePath,
  }) async {
    tester.view.physicalSize = switch (c.companionWindows?.kind) {
      CompanionWindowKind.xenoSettings => const Size(330, 270),
      CompanionWindowKind.xenoScripts ||
      CompanionWindowKind.xenoClients => const Size(300, 200),
      _ => const Size(700, 400),
    };
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final shellKey = key ?? GlobalKey<XenoShellState>();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            UiScaleViewport(scale: c.uiScale, child: child!),
        home: XenoShell(
          key: shellKey,
          controller: c,
          nativeWindow: false,
          onBackToOrion: back ?? () {},
          editorService: service,
          pickScriptPath: pickScriptPath,
          pickSavePath: pickSavePath,
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
    'Xeno title close and native close return to Orion with the active draft intact',
    (tester) async {
      final c = OriginalPortController();
      final key = GlobalKey<XenoShellState>();
      var returned = 0;
      await mount(tester, c, key: key, back: () => returned++);
      final id = c.activeDocumentId;
      c.updateDocumentContent(id, 'print("close preserves draft")');
      await tester.pump();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(returned, 1);
      key.currentState!.onWindowClose();
      await tester.pumpAndSettle();
      expect(returned, 2);
      expect(c.activeDocumentId, id);
      expect(c.activeDocument.content, 'print("close preserves draft")');
      expect(c.activeDocument.isDirty, true);
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'Xeno keeps source editor geometry and disables execution without a bridge',
    (tester) async {
      final c = OriginalPortController();
      await mount(tester, c);
      expect(find.text('Xeno'), findsOneWidget);
      expect(find.text('v1.0.8'), findsOneWidget);
      final code = tester.getRect(find.byKey(const ValueKey('code-editor')));
      expect(code.top, 47);
      expect(code.bottom, 358);
      expect(
        tester
            .widget<XenoIconButton>(find.byKey(const ValueKey('xeno-execute')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('xeno-back-to-orion')), findsNothing);
      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
      expect(c.activeDocument.content, '');
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'Xeno Open replaces the current model from fresh file contents and Save always asks for a location',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('xeno-picker-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/loaded.lua')
        ..writeAsStringSync('print("first")');
      final c = OriginalPortController();
      final originalId = c.activeDocumentId;
      final id = c.newDocument(
        name: 'loaded.lua',
        content: 'print("initial")',
      ).id;
      c.selectDocument(id);
      var savedPickers = 0;
      await mount(
        tester,
        c,
        pickScriptPath: () async => file.path,
        pickSavePath: (name) async {
          savedPickers++;
          return '${directory.path}/saved.lua';
        },
      );
      Future<void> openFile() async {
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('Open'));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
      }

      await openFile();
      expect(c.activeDocumentId, id);
      expect(c.documents, hasLength(2));
      expect(c.documents.first.id, originalId);
      expect(c.activeDocument.content, 'print("first")');
      expect(c.activeDocument.filePath, file.path);
      expect(c.activeDocument.isDirty, false);
      file.writeAsStringSync('print("changed on disk")');
      await openFile();
      expect(c.activeDocumentId, id);
      expect(c.documents, hasLength(2));
      expect(c.activeDocument.content, 'print("changed on disk")');
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('Save'));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
      }
      expect(savedPickers, 2);
      expect(c.savedPaths, hasLength(2));
      expect(c.savedBody, 'print("changed on disk")');
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'Xeno toolbar opens separate companions and keeps the main editor size and Monaco active',
    (tester) async {
      final windows = XenoTestWindows();
      final c = OriginalPortController()..companionWindows = windows;
      final channel = OriginalPortChannel();
      final service = MonacoEditorService(
        channel: channel,
        server: OriginalPortAssets(),
        onChange: c.updateDocumentContent,
        onShortcut: (_) {},
      );
      await mount(tester, c, service: service);
      final bounds = tester.getRect(find.byKey(const ValueKey('code-editor')));
      for (final key in ['xeno-settings', 'xeno-scripts', 'xeno-clients']) {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('code-editor'))),
          bounds,
        );
        expect(find.text('Xeno'), findsOneWidget);
        expect(service.visible, true);
      }
      expect(windows.opened, [
        CompanionWindowKind.xenoSettings,
        CompanionWindowKind.xenoScripts,
        CompanionWindowKind.xenoClients,
      ]);
      await cleanup(tester, c);
      service.dispose();
    },
  );

  testWidgets(
    'Xeno Settings is an independent fixed size view without a second Monaco and closes only itself',
    (tester) async {
      final windows = XenoTestWindows(kind: CompanionWindowKind.xenoSettings);
      final c = OriginalPortController()..companionWindows = windows;
      final id = c.activeDocumentId;
      c.updateDocumentContent(id, 'print("dirty")');
      final channel = OriginalPortChannel();
      final service = MonacoEditorService(
        channel: channel,
        server: OriginalPortAssets(),
        onChange: c.updateDocumentContent,
        onShortcut: (_) {},
      );
      final key = GlobalKey<XenoShellState>();
      await mount(tester, c, key: key, service: service);
      expect(find.text('Interface settings'), findsOneWidget);
      expect(find.text('Orion Bridge'), findsOneWidget);
      expect(find.byKey(const ValueKey('code-editor')), findsNothing);
      expect(channel.snapshot, isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('xeno-settings'))),
        const Size(330, 270),
      );
      await tester.tap(find.byKey(const ValueKey('xeno-close-panel')));
      await tester.pumpAndSettle();
      expect(windows.closed, 1);
      expect(windows.returned, 0);
      key.currentState!.onWindowClose();
      await tester.pumpAndSettle();
      expect(windows.closed, 2);
      await tester.tap(find.byKey(const ValueKey('xeno-back-to-orion')));
      await tester.pumpAndSettle();
      expect(windows.returned, 1);
      expect(c.activeDocumentId, id);
      expect(c.activeDocument.content, 'print("dirty")');
      await cleanup(tester, c);
      service.dispose();
    },
  );

  testWidgets(
    'Xeno Scripts reads its source directory snapshot and only offers gated execution',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('xeno-scripts-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final c = OriginalPortController()
        ..companionWindows = XenoTestWindows(
          kind: CompanionWindowKind.xenoScripts,
        )
        ..setInterfacePreference(
          InterfacePreset.xeno,
          'scriptsDirectory',
          directory.path,
        );
      await mount(tester, c);
      expect(find.text('No scripts found'), findsOneWidget);
      File(
        '${directory.path}/real-file.lua',
      ).writeAsStringSync('print("real")');
      await mount(tester, c);
      expect(find.text('real-file'), findsOneWidget);
      expect(
        tester
            .widget<XenoTextButton>(
              find.widgetWithText(XenoTextButton, 'Execute'),
            )
            .onPressed,
        isNull,
      );
      final id = c.activeDocumentId;
      await tester.tap(find.text('real-file'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('real-file'));
      await tester.pumpAndSettle();
      expect(c.activeDocumentId, id);
      expect(c.documents, hasLength(1));
      await cleanup(tester, c);
    },
  );

  testWidgets('Xeno Clients has the source independent empty panel', (
    tester,
  ) async {
    final c = OriginalPortController()
      ..companionWindows = XenoTestWindows(
        kind: CompanionWindowKind.xenoClients,
      );
    await mount(tester, c);
    expect(
      tester.getSize(find.byKey(const ValueKey('xeno-clients'))),
      const Size(300, 200),
    );
    expect(find.text('No clients connected'), findsOneWidget);
    expect(find.byKey(const ValueKey('code-editor')), findsNothing);
    await cleanup(tester, c);
  });

  testWidgets(
    'Xeno native snapshot has source theme and font rules and all shared models',
    (tester) async {
      final c = OriginalPortController()
        ..newDocument(name: 'native.lua', content: 'print("hello")');
      final channel = OriginalPortChannel();
      final service = MonacoEditorService(
        channel: channel,
        server: OriginalPortAssets(),
        onChange: c.updateDocumentContent,
        onShortcut: (_) {},
      );
      await mount(tester, c, service: service);
      expect(channel.snapshot?['options']['shell'], 'originalXeno');
      expect(channel.snapshot?['options']['fontSize'], 13);
      expect(channel.snapshot?['options']['background'], '#050505');
      expect((channel.snapshot?['documents'] as List).length, 2);
      expect(channel.snapshot?['activeId'], c.activeDocumentId);
      await cleanup(tester, c);
      service.dispose();
    },
  );

  for (final scale in [.8, 1.0, 1.25]) {
    testWidgets(
      'Xeno main and native Settings remain usable at GUI scale $scale',
      (tester) async {
        final c = OriginalPortController()..setUiScale(scale);
        await mount(tester, c);
        expect(tester.takeException(), isNull);
        c.companionWindows = XenoTestWindows(
          kind: CompanionWindowKind.xenoSettings,
        );
        await mount(tester, c);
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('xeno-back-to-orion')),
          findsOneWidget,
        );
        await cleanup(tester, c);
      },
    );
  }
}
