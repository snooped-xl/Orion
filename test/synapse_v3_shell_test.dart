import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_models.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/companion_window.dart';
import 'package:orion/screens/workspace_screen.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/synapse_v3/synapse_v3_shell.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

class _Controller extends OrionController {
  _Controller() : super(useMacSploit: false);

  String? savedId, savedSource, executedSource, executedName;
  int opened = 0;
  @override
  Future<void> flushPersistence() async {}
  @override
  Future<EditorDocument?> openFile() async {
    opened++;
    return newDocument(name: 'opened.luau', content: 'print("opened")');
  }

  @override
  Future<bool> saveDocument([String? id]) async {
    savedId = id ?? activeDocumentId;
    savedSource = documents.firstWhere((d) => d.id == savedId).content;
    return true;
  }

  @override
  void execute({String? source, String? name}) {
    executedSource = source ?? activeDocument.content;
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

class _V3Companions implements CompanionWindowHost {
  _V3Companions(this.controller);
  final OrionController controller;
  CompanionWindowKind? openedKind;
  String? openedId;
  @override
  bool get isChildWindow => false;
  @override
  CompanionWindowKind? get kind => null;
  @override
  String? get documentId => null;
  @override
  Future<void> open(CompanionWindowKind kind, {String? documentId}) async {
    openedKind = kind;
    openedId = documentId;
    controller.setDocumentDetached(documentId!, true);
    final remaining = controller.documents.where(
      (doc) => !controller.detachedDocumentIds.contains(doc.id),
    );
    if (remaining.isEmpty) {
      controller.newDocument(name: 'Script');
    } else {
      controller.selectDocument(remaining.first.id);
    }
  }

  @override
  Future<void> close() async {}
  @override
  Future<void> closeAll() async {}
  @override
  Future<void> focusMain() async {}
  @override
  Future<void> returnToOrion() async {}
  @override
  Future<void> updateOwnerWindow({
    bool? alwaysOnTop,
    bool? resizable,
    double? opacity,
  }) async {}
}

class _Channel extends MethodChannel {
  _Channel() : super('orion/v3-test-editor');
  Future<dynamic> Function(MethodCall)? handler;
  final calls = <MethodCall>[];
  final commands = <Map<String, dynamic>>[];
  Map<String, dynamic>? snapshot;
  Completer<void>? captureGate;
  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall)? callback) {
    handler = callback;
  }

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    calls.add(MethodCall(method, arguments));
    if (method == 'capturePreview') await captureGate?.future;
    if (method == 'create') {
      await handler?.call(MethodCall('message', jsonEncode({'type': 'ready'})));
    } else if (method == 'send') {
      final command = jsonDecode(arguments as String) as Map<String, dynamic>;
      commands.add(command);
      if (command['type'] == 'sync') snapshot = command;
      if (command['type'] == 'flush') {
        final document = (snapshot!['documents'] as List).firstWhere(
          (d) => d['id'] == snapshot!['activeId'],
        );
        await handler?.call(
          MethodCall(
            'message',
            jsonEncode({
              'type': 'flush',
              'requestId': command['requestId'],
              'id': document['id'],
              'content': document['content'],
            }),
          ),
        );
      }
    }
    return null;
  }

  Map get bounds =>
      calls.lastWhere((call) => call.method == 'setBounds').arguments as Map;
}

Widget _fixture(
  _Controller controller, {
  MonacoEditorService? service,
  GlobalKey<SynapseV3ShellState>? key,
  VoidCallback? onBack,
  bool bridgeReady = false,
}) => MaterialApp(
  theme: orionTheme(Brightness.dark, controller.accentColor),
  builder: (context, child) =>
      UiScaleViewport(scale: controller.uiScale, child: child!),
  home: SynapseV3Shell(
    key: key,
    controller: controller,
    nativeWindow: false,
    editorService: service,
    onBackToOrion: onBack ?? () {},
    bridgeReady: bridgeReady,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in const [
      ('SynapseInter', 'assets/synapse_v3/fonts/Inter-Regular.ttf'),
      ('SynapseRubik', 'assets/synapse_v3/fonts/Rubik-Regular.ttf'),
      ('JetBrainsMono', 'assets/fonts/JetBrainsMono.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  Future<void> mount(
    WidgetTester tester,
    _Controller controller, {
    Size size = const Size(961, 461),
    MonacoEditorService? service,
    GlobalKey<SynapseV3ShellState>? key,
    VoidCallback? onBack,
    bool bridgeReady = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      _fixture(
        controller,
        service: service,
        key: key,
        onBack: onBack,
        bridgeReady: bridgeReady,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('source V3 chrome dimensions and five original actions', (
    tester,
  ) async {
    final controller = _Controller()..setReducedMotion(true);
    var backed = false;
    try {
      await mount(tester, controller, onBack: () => backed = true);
      final body = tester.getRect(find.byKey(const ValueKey('v3-editor-body')));
      expect(body, const Rect.fromLTWH(1, 87, 760, 328));
      final execute = find.byTooltip('Execute script · Ctrl Enter');
      expect(tester.getRect(execute), const Rect.fromLTWH(4, 422, 91, 33));
      for (final tooltip in [
        'Execute script · Ctrl Enter',
        'Clear script',
        'Open file · Ctrl O',
        'Execute file',
        'Save file · Ctrl S',
        'Connect Orion Bridge',
        'Show console',
        'Find in editor (Ctrl+F)',
      ]) {
        expect(
          find.byTooltip(tooltip).hitTestable(),
          findsOneWidget,
          reason: tooltip,
        );
      }
      expect(find.text('Execute'), findsNWidgets(2));
      for (final tooltip in ['Execute script · Ctrl Enter', 'Execute file']) {
        final button = tester.widget<TextButton>(
          find.descendant(
            of: find.byTooltip(tooltip),
            matching: find.byType(TextButton),
          ),
        );
        expect(button.onPressed, isNull);
        expect(
          button.style!.foregroundColor!.resolve({WidgetState.disabled}),
          const Color(0xFF5A5A5A),
        );
        await tester.tap(find.byTooltip(tooltip));
      }
      expect(controller.executedSource, isNull);
      expect(find.text('Local Filesystem'), findsOneWidget);
      expect(find.byTooltip('Editor'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(find.byTooltip('Script Hub'), findsOneWidget);
      expect(find.byTooltip('Theme'), findsOneWidget);
      expect(find.byTooltip('Scripts'), findsNothing);
      expect(find.text('Auto Execute'), findsNothing);
      expect(find.text('Back to Orion'), findsNothing);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('v3-back-to-orion')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('v3-back-to-orion')));
      expect(backed, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  testWidgets('editing open save clear new and original rename popup work', (
    tester,
  ) async {
    final controller = _Controller()..setReducedMotion(true);
    controller.updateSynapsePreferences(
      defaultTabContent: '-- configured default',
    );
    try {
      await mount(tester, controller);
      final editor = find.byKey(const ValueKey('code-editor'));
      await tester.enterText(editor, 'print("exact saved body")');
      await tester.tap(find.byTooltip('Save file · Ctrl S'));
      await tester.pumpAndSettle();
      expect(controller.savedSource, 'print("exact saved body")');
      await tester.tap(find.byTooltip('Open file · Ctrl O'));
      await tester.pumpAndSettle();
      expect(controller.opened, 1);
      expect(controller.activeDocument.name, 'opened.luau');
      expect(
        tester.widget<TextField>(editor).controller!.text,
        'print("opened")',
      );
      await tester.tap(find.byTooltip('Clear script'));
      await tester.pumpAndSettle();
      expect(controller.activeDocument.content, isEmpty);
      expect(find.text('Clear script?'), findsNothing);
      await tester.tap(find.byTooltip('New script'));
      await tester.pumpAndSettle();
      expect(controller.activeDocument.content, '-- configured default');
      final id = controller.activeDocumentId;
      final tab = find.byKey(ValueKey('v3-tab-$id'));
      await tester.tap(tab, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Input the new tab name below.'), findsOneWidget);
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect((dialog.child! as SizedBox).width, 384);
      expect((dialog.child! as SizedBox).height, 203);
      await tester.enterText(
        find.byKey(const ValueKey('v3-rename-input')),
        'renamed.luau',
      );
      await tester.tap(find.text('Ok'));
      await tester.pumpAndSettle();
      expect(controller.activeDocument.name, 'renamed.luau');
      await tester.tap(find.byTooltip('Close renamed.luau'));
      await tester.pumpAndSettle();
      expect(controller.documents.any((d) => d.id == id), isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  testWidgets(
    'manual execute file uses exact selected source and preserves active tabs',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('v3-manual-execute-'),
      ))!;
      final file = File('${directory.path}/manual.luau');
      const body = '-- chosen file\nlocal part = Instance.new("Part")\n';
      await tester.runAsync(() => file.writeAsString(body));
      const picker = MethodChannel('plugins.flutter.io/file_selector');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            picker,
            (call) async => call.method == 'openFile' ? [file.path] : null,
          );
      final controller = _Controller()..setReducedMotion(true);
      final activeId = controller.activeDocumentId;
      final activeBody = controller.activeDocument.content;
      try {
        await mount(tester, controller, bridgeReady: true);
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('Execute file'));
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pumpAndSettle();
        expect(controller.executedSource, body);
        expect(controller.executedName, 'manual.luau');
        expect(controller.activeDocumentId, activeId);
        expect(controller.activeDocument.content, activeBody);
        expect(controller.documents, hasLength(1));
        expect(controller.activities.first.title, 'No clients connected');
        expect(tester.takeException(), isNull);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(picker, null);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    },
  );

  testWidgets(
    'all actions and console fit scaled reference and minimum windows',
    (tester) async {
      final controller = _Controller()..setReducedMotion(true);
      try {
        for (final size in [const Size(961, 461), const Size(720, 400)]) {
          await mount(tester, controller, size: size);
          for (final scale in [.8, 1.0, 1.25]) {
            controller.setUiScale(scale);
            await tester.pumpWidget(_fixture(controller));
            await tester.pumpAndSettle();
            for (final tooltip in [
              'Execute script · Ctrl Enter',
              'Clear script',
              'Open file · Ctrl O',
              'Execute file',
              'Save file · Ctrl S',
              'Connect Orion Bridge',
              'Show console',
            ]) {
              expect(
                find.byTooltip(tooltip).hitTestable(),
                findsOneWidget,
                reason: '$size/$scale $tooltip',
              );
            }
            await tester.tap(find.byTooltip('Show console'));
            await tester.pumpAndSettle();
            expect(find.text('Console'), findsOneWidget);
            final body = tester.getSize(
              find.byKey(const ValueKey('v3-editor-body')),
            );
            expect(body.height, greaterThanOrEqualTo(95));
            expect(
              tester.takeException(),
              isNull,
              reason: '$size/$scale console',
            );
            await tester.tap(find.byTooltip('Hide console'));
            await tester.pumpAndSettle();
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'shared native service survives switching shells with models and geometry',
    (tester) async {
      final controller = _Controller()..setReducedMotion(true);
      final channel = _Channel();
      final service = MonacoEditorService(
        channel: channel,
        server: _Assets(),
        onChange: controller.updateDocumentContent,
        onShortcut: (_) {},
      );
      try {
        await mount(tester, controller, service: service);
        expect(channel.bounds['x'], 1);
        expect(channel.bounds['y'], 87);
        expect(channel.bounds['width'], 760);
        expect(channel.bounds['height'], 328);
        expect(channel.snapshot!['options']['background'], '#000000');
        final body = controller.activeDocument.content;
        channel.captureGate = Completer<void>();
        final menuStart = channel.calls.length;
        await tester.tap(
          find.byKey(ValueKey('v3-tab-${controller.activeDocumentId}')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('Duplicate'), findsNothing);
        expect(service.visible, isTrue);
        expect(
          channel.calls
              .skip(menuStart)
              .any((call) => call.method == 'capturePreview'),
          true,
        );
        channel.captureGate!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Duplicate'), findsOneWidget);
        expect(service.visible, isFalse);
        final menuCalls = channel.calls.skip(menuStart).toList();
        final capture = menuCalls.indexWhere(
          (call) => call.method == 'capturePreview',
        );
        final hidden = menuCalls.indexWhere(
          (call) =>
              call.method == 'setBounds' &&
              (call.arguments as Map)['visible'] == false,
        );
        expect(hidden, greaterThan(capture));
        await tester.tapAt(const Offset(950, 450));
        await tester.pumpAndSettle();
        expect(service.visible, isTrue);
        expect(controller.activeDocument.content, body);
        await tester.pumpWidget(
          MaterialApp(
            theme: orionTheme(Brightness.dark, controller.accentColor),
            home: Scaffold(
              body: WorkspaceScreen(
                controller: controller,
                editorService: service,
                onLibrary: () {},
                onSave: () {},
                onOpen: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(service.ready, isTrue);
        expect(channel.calls.where((c) => c.method == 'dispose'), isEmpty);
        await tester.pumpWidget(_fixture(controller, service: service));
        await tester.pumpAndSettle();
        expect(channel.calls.where((c) => c.method == 'create'), hasLength(1));
        expect(controller.activeDocument.content, body);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        service.dispose();
      }
    },
  );

  testWidgets(
    'V3 console shortcut, header resize and open state survive remount',
    (tester) async {
      final controller = _Controller()..setReducedMotion(true);
      try {
        await mount(tester, controller);
        await tester.tapAt(
          tester.getTopLeft(find.byKey(const ValueKey('v3-editor-body'))) +
              const Offset(80, 30),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.f9);
        await tester.pumpAndSettle();
        expect(find.text('Console'), findsOneWidget);
        expect(find.text('No output yet.'), findsOneWidget);
        expect(find.textContaining('Workspace ready'), findsNothing);
        final header = find.byKey(const ValueKey('v3-console-resize'));
        expect(tester.getSize(header).height, 30);
        final initial = controller.synapsePreferences.consoleHeight;
        await tester.drag(header, const Offset(0, -35));
        await tester.pumpAndSettle();
        expect(
          controller.synapsePreferences.consoleHeight,
          greaterThan(initial),
        );
        expect(
          controller.getInterfacePreferences(
            InterfacePreset.synapseV3,
          )['consoleOpen'],
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_fixture(controller));
        await tester.pumpAndSettle();
        expect(find.text('Console'), findsOneWidget);
        await tester.tapAt(
          tester.getTopLeft(find.byKey(const ValueKey('v3-editor-body'))) +
              const Offset(80, 30),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.f9);
        await tester.pumpAndSettle();
        expect(find.text('Console'), findsNothing);
        expect(
          controller.getInterfacePreferences(
            InterfacePreset.synapseV3,
          )['consoleOpen'],
          isFalse,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'manual Undock uses the native host and preserves the dirty tab',
    (tester) async {
      final controller = _Controller()..setReducedMotion(true);
      final host = _V3Companions(controller);
      controller.companionWindows = host;
      final document = controller.newDocument(
        name: 'detached.luau',
        content: 'print("keep my draft")',
      );
      const draft = 'print("keep my draft")\n-- unsaved';
      controller.updateDocumentContent(document.id, draft);
      try {
        await mount(tester, controller);
        await tester.tap(
          find.byKey(ValueKey('v3-tab-${document.id}')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Undock'));
        await tester.pumpAndSettle();
        expect(host.openedKind, CompanionWindowKind.synapseV3Editor);
        expect(host.openedId, document.id);
        expect(controller.detachedDocumentIds, contains(document.id));
        expect(find.byKey(ValueKey('v3-tab-${document.id}')), findsNothing);
        final preserved = controller.documents.firstWhere(
          (doc) => doc.id == document.id,
        );
        expect(preserved.content, draft);
        expect(preserved.isDirty, isTrue);
        controller.setDocumentDetached(document.id, false);
        controller.selectDocument(document.id);
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('v3-tab-${document.id}')), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('code-editor')))
              .controller!
              .text,
          draft,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
}
