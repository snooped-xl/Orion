import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/companion_window.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/synapse_v3/v3_undocked_editor.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

import 'original_awp_test.dart' show OriginalPortAssets, OriginalPortChannel;

class _ChildHost implements CompanionWindowHost {
  _ChildHost(this.documentId, {this.onClose});
  @override
  final String documentId;
  final VoidCallback? onClose;
  int closes = 0;
  @override
  bool get isChildWindow => true;
  @override
  CompanionWindowKind get kind => CompanionWindowKind.synapseV3Editor;
  @override
  Future<void> close() async {
    closes++;
    onClose?.call();
  }

  @override
  Future<void> closeAll() async {}
  @override
  Future<void> focusMain() async {}
  @override
  Future<void> open(CompanionWindowKind kind, {String? documentId}) async {}
  @override
  Future<void> returnToOrion() async {}
  @override
  Future<void> updateOwnerWindow({
    bool? alwaysOnTop,
    bool? resizable,
    double? opacity,
  }) async {}
}

class _FlushChannel extends OriginalPortChannel {
  String? pendingContent;
  int flushes = 0;
  @override
  Future<T?> invokeMethod<T>(String method, [dynamic args]) async {
    if (method == 'send') {
      final value = jsonDecode(args as String) as Map;
      if (value['type'] == 'flush' && pendingContent != null) {
        flushes++;
        final content = pendingContent!;
        pendingContent = null;
        await handler?.call(
          MethodCall(
            'message',
            jsonEncode({
              'type': 'flush',
              'id': snapshot!['activeId'],
              'content': content,
              'requestId': value['requestId'],
            }),
          ),
        );
        return null;
      }
    }
    return super.invokeMethod<T>(method, args);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('SynapseInter')..addFont(
          rootBundle.load('assets/synapse_v3/fonts/Inter-Regular.ttf'),
        ))
        .load();
  });

  Future<void> mount(
    WidgetTester tester,
    OrionController c, {
    GlobalKey<V3UndockedEditorState>? key,
    MonacoEditorService? service,
    Size size = const Size(720, 446),
    Future<String?> Function()? pickScriptPath,
    Future<String?> Function(String)? pickSavePath,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => UiScaleViewport(scale: c.uiScale, child: child!),
        home: V3UndockedEditor(
          key: key,
          controller: c,
          nativeWindow: false,
          editorService: service,
          pickScriptPath: pickScriptPath,
          pickSavePath: pickSavePath,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> cleanup(WidgetTester tester, OrionController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  testWidgets(
    'undocked V3 matches source chrome, editor inset, exact actions and disconnected controls',
    (tester) async {
      final c = OrionController(persistChanges: false);
      c.renameDocument(c.activeDocumentId, 'Local Script');
      c.companionWindows = _ChildHost(c.activeDocumentId);
      await mount(tester, c);
      expect(find.text('Undocked editor - Local Script'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('v3-undocked-editor'))),
        const Rect.fromLTRB(1, 45, 719, 400),
      );
      final labels = tester
          .widgetList<TextButton>(find.byType(TextButton))
          .map((b) => (b.child as Row).children.last as Text)
          .map((t) => t.data)
          .toList();
      expect(labels, ['Execute', 'Clear', 'Open', 'Save', 'Execute', 'Redock']);
      for (final tooltip in ['Execute script', 'Execute file']) {
        final action = find.byKey(ValueKey('v3-undocked-action-$tooltip'));
        expect(tester.getSize(action), const Size(91, 33));
        expect(
          tester
              .widget<TextButton>(
                find.descendant(of: action, matching: find.byType(TextButton)),
              )
              .onPressed,
          isNull,
        );
      }
      expect(
        tester
            .getRect(
              find.byKey(const ValueKey('v3-undocked-action-Clear script')),
            )
            .top,
        407,
      );
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'edits and Open stay pinned to the detached document and Save reuses its actual path',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'v3-undocked-files-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/my-detached_script.lua')
        ..writeAsStringSync('print("opened")');
      final c = OrionController(persistChanges: false);
      final pinned = c.activeDocumentId;
      final other = c.newDocument(name: 'Another', content: 'print("other")');
      c.updateDocumentContent(other.id, 'print("parent dirty")');
      c.setDocumentDetached(pinned, true);
      c.companionWindows = _ChildHost(pinned);
      var pickSaveCount = 0;
      await mount(
        tester,
        c,
        pickScriptPath: () async => file.path,
        pickSavePath: (_) async {
          pickSaveCount++;
          return '${directory.path}/new.lua';
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('v3-undocked-editor')),
        'print("detached")',
      );
      await tester.pumpAndSettle();
      expect(
        c.documents.firstWhere((d) => d.id == pinned).content,
        'print("detached")',
      );
      expect(c.activeDocumentId, other.id);
      await tester.runAsync(() async {
        final opened = Completer<void>();
        void onOpened() {
          final document = c.documents.firstWhere((d) => d.id == pinned);
          if (document.content == 'print("opened")' &&
              document.name == 'My Detached Script' &&
              !opened.isCompleted) {
            opened.complete();
          }
        }

        c.addListener(onOpened);
        try {
          await tester.tap(
            find.byKey(const ValueKey('v3-undocked-action-Open file')),
          );
          await opened.future.timeout(const Duration(seconds: 5));
        } finally {
          c.removeListener(onOpened);
        }
      });
      await tester.pumpAndSettle();
      expect(c.documents, hasLength(2));
      expect(c.activeDocumentId, other.id);
      expect(c.activeDocument.isDirty, true);
      expect(
        c.documents.firstWhere((d) => d.id == pinned).name,
        'My Detached Script',
      );
      expect(
        c.documents.firstWhere((d) => d.id == pinned).content,
        'print("opened")',
      );
      expect(
        c.documents.firstWhere((d) => d.id == other.id).content,
        'print("parent dirty")',
      );
      await tester.enterText(
        find.byKey(const ValueKey('v3-undocked-editor')),
        'print("saved")',
      );
      await tester.runAsync(() async {
        final saved = Completer<void>();
        void onSaved() {
          final document = c.documents.firstWhere((d) => d.id == pinned);
          if (document.savedContent == 'print("saved")' &&
              !document.isDirty &&
              !saved.isCompleted) {
            saved.complete();
          }
        }

        c.addListener(onSaved);
        try {
          await tester.tap(
            find.byKey(const ValueKey('v3-undocked-action-Save file')),
          );
          await saved.future.timeout(const Duration(seconds: 5));
        } finally {
          c.removeListener(onSaved);
        }
      });
      await tester.pumpAndSettle();
      expect(pickSaveCount, 0);
      expect(file.readAsStringSync(), 'print("saved")');
      expect(c.documents.firstWhere((d) => d.id == pinned).isDirty, false);
      expect(c.activeDocumentId, other.id);
      expect(c.activeDocument.isDirty, true);
      await tester.tap(
        find.byKey(const ValueKey('v3-undocked-action-Clear script')),
      );
      await tester.pumpAndSettle();
      expect(c.documents.firstWhere((d) => d.id == pinned).content, '');
      expect(c.activeDocumentId, other.id);
      expect(c.activeDocument.isDirty, true);
      expect(
        c.documents.firstWhere((d) => d.id == other.id).content,
        'print("parent dirty")',
      );
      await cleanup(tester, c);
    },
  );

  testWidgets(
    'redock flushes the newest isolated Monaco value before host closure and never disposes the root service',
    (tester) async {
      final c = OrionController(persistChanges: false);
      final id = c.activeDocumentId;
      c.newDocument(name: 'Other');
      String? closedBody;
      final host = _ChildHost(
        id,
        onClose: () =>
            closedBody = c.documents.firstWhere((d) => d.id == id).content,
      );
      c.companionWindows = host;
      final channel = _FlushChannel();
      final service = MonacoEditorService(
        channel: channel,
        server: OriginalPortAssets(),
        onChange: c.updateDocumentContent,
        onShortcut: (_) {},
      );
      final key = GlobalKey<V3UndockedEditorState>();
      await mount(tester, c, key: key, service: service);
      expect(channel.snapshot!['documents'], hasLength(1));
      expect(channel.snapshot!['activeId'], id);
      expect(channel.snapshot!['options']['shell'], 'synapseV3');
      channel.pendingContent = 'print("latest native draft")';
      await tester.tap(find.byKey(const ValueKey('v3-undocked-action-Redock')));
      await tester.pumpAndSettle();
      expect(host.closes, 1);
      expect(channel.flushes, 1);
      expect(closedBody, 'print("latest native draft")');
      expect(find.text('Returning…'), findsOneWidget);
      expect(service.visible, false);
      await key.currentState!.redock();
      expect(host.closes, 1);
      await cleanup(tester, c);
      expect(service.ready, true);
      service.dispose();
    },
  );

  for (final scale in [.8, 1.0, 1.25]) {
    testWidgets(
      'undocked source geometry respects GUI scale $scale at its default window size',
      (tester) async {
        final c = OrionController(persistChanges: false)..setUiScale(scale);
        c.companionWindows = _ChildHost(c.activeDocumentId);
        await mount(tester, c);
        expect(tester.takeException(), isNull);
        final rect = tester.getRect(
          find.byKey(const ValueKey('v3-undocked-editor')),
        );
        expect(rect.left, closeTo(scale, .001));
        expect(rect.top, closeTo(45 * scale, .001));
        expect(rect.right, closeTo(720 - scale, .001));
        expect(rect.bottom, closeTo(446 - 46 * scale, .001));
        expect(find.text('Redock'), findsOneWidget);
        await cleanup(tester, c);
      },
    );
  }
}
