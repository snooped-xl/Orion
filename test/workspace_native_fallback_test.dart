import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/screens/workspace_screen.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';

class _Assets extends EditorAssetServer {
  @override
  Future<Uri> start() async =>
      Uri.parse('http://127.0.0.1:9999/editor/index.html');

  @override
  Future<void> close() async {}
}

class _Channel extends MethodChannel {
  _Channel() : super('orion/startup-fallback-test');

  Future<dynamic> Function(MethodCall)? handler;
  Completer<void>? creationGate;
  bool failCreate = false;

  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall)? callback) =>
      handler = callback;

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    if (method == 'create') {
      if (failCreate) {
        throw PlatformException(
          code: 'fixture-error',
          message: 'WebKit failed',
        );
      }
      await creationGate?.future;
      await handler?.call(MethodCall('message', jsonEncode({'type': 'ready'})));
    }
    return null;
  }
}

void main() {
  const editor = ValueKey('code-editor');
  const source = 'local message = "preserved source"\nprint(message)';

  setUpAll(() async {
    for (final font in [
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Regular.ttf'),
      ('JetBrainsMono', 'assets/fonts/JetBrainsMono.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  testWidgets(
    'inactive and obscured native editor paints preserved code without editing',
    (tester) async {
      final controller = OrionController(persistChanges: false)
        ..setReducedMotion(true);
      controller.updateDocumentContent(controller.activeDocumentId, source);
      final service = _service(_Channel());
      try {
        await _mount(tester, controller, service: service, active: false);
        expect(service.ready, isTrue);
        expect(service.visible, isFalse);
        final fallback = tester.widget<TextField>(find.byKey(editor));
        expect(fallback.controller!.text, source);
        expect(fallback.readOnly, isTrue);
        expect(fallback.focusNode!.canRequestFocus, isFalse);
        await tester.tapAt(tester.getCenter(find.byKey(editor)));
        await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
        await tester.pump();
        expect(fallback.focusNode!.hasFocus, isFalse);
        expect(controller.activeDocument.content, source);

        await _mount(tester, controller, service: service);
        expect(service.visible, isTrue);
        expect(find.byKey(editor), findsNothing);

        service.setObscured(true, owner: 'intro-test');
        await tester.pumpAndSettle();
        expect(find.byKey(editor), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byKey(editor)).controller!.text,
          source,
        );
        controller.updateDocumentContent(
          controller.activeDocumentId,
          'print("latest native source")',
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byKey(editor)).controller!.text,
          'print("latest native source")',
        );
        service.setObscured(false, owner: 'intro-test');
        await tester.pumpAndSettle();
        expect(service.visible, isTrue);
        expect(find.byKey(editor), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
        controller.dispose();
      }
    },
  );

  testWidgets('loading WebKit paints the same read-only source immediately', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false)
      ..setReducedMotion(true);
    controller.updateDocumentContent(controller.activeDocumentId, source);
    final gate = Completer<void>();
    final channel = _Channel()..creationGate = gate;
    final service = _service(channel);
    try {
      await _mount(tester, controller, service: service, active: false);
      expect(service.ready, isFalse);
      expect(service.error, isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final fallback = tester.widget<TextField>(find.byKey(editor));
      expect(fallback.controller!.text, source);
      expect(fallback.readOnly, isTrue);
      gate.complete();
      await tester.pumpAndSettle();
      expect(service.ready, isTrue);
      expect(find.byKey(editor), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
      controller.dispose();
    }
  });

  testWidgets(
    'native initialization errors keep the existing error and retry',
    (tester) async {
      final controller = OrionController(persistChanges: false)
        ..setReducedMotion(true);
      controller.updateDocumentContent(controller.activeDocumentId, source);
      final service = _service(_Channel()..failCreate = true);
      try {
        await _mount(tester, controller, service: service, active: false);
        expect(service.ready, isFalse);
        expect(service.error, contains('WebKit failed'));
        expect(find.byKey(editor), findsNothing);
        expect(find.text('Retry editor'), findsOneWidget);
        expect(find.textContaining('WebKit failed'), findsOneWidget);
        expect(controller.activeDocument.content, source);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
        controller.dispose();
      }
    },
  );

  testWidgets('the ordinary Flutter editor remains editable without Monaco', (
    tester,
  ) async {
    final controller = OrionController(persistChanges: false)
      ..setReducedMotion(true);
    controller.updateDocumentContent(controller.activeDocumentId, source);
    try {
      await _mount(tester, controller);
      expect(tester.widget<TextField>(find.byKey(editor)).readOnly, isFalse);
      await tester.enterText(find.byKey(editor), 'print("still editable")');
      await tester.pumpAndSettle();
      expect(controller.activeDocument.content, 'print("still editable")');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });
}

MonacoEditorService _service(_Channel channel) => MonacoEditorService(
  channel: channel,
  server: _Assets(),
  onChange: (_, _) {},
  onShortcut: (_) {},
);

Future<void> _mount(
  WidgetTester tester,
  OrionController controller, {
  MonacoEditorService? service,
  bool active = true,
}) async {
  tester.view.physicalSize = const Size(822, 523);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        theme: orionTheme(Brightness.dark, controller.accentColor),
        home: Scaffold(
          body: WorkspaceScreen(
            controller: controller,
            editorService: service,
            active: active,
            onLibrary: () {},
            onOpen: () {},
            onSave: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
