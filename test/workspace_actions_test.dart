import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart';
import 'package:orion/screens/workspace_screen.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/connected_action_group.dart';

void main() {
  late Directory storage;
  late OrionController controller;

  setUp(() async {
    storage = await Directory.systemTemp.createTemp('orion-actions-');
    controller = _ActionController(storageDirectory: storage);
    await controller.initialize();
    controller.completeIntro();
    controller.setReducedMotion(true);
  });

  void cleanUp(WidgetTester tester) {
    addTearDown(
      () => tester.runAsync(() async {
        controller.dispose();
        await controller.flushPersistence();
        await storage.delete(recursive: true);
      }),
    );
  }

  Future<void> pumpApp(WidgetTester tester) async {
    cleanUp(tester);
    tester.view.physicalSize = const Size(860, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      OrionApp(controller: controller, nativeWindow: false),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('primary file and executor controls stay visible at 860 by 600', (
    tester,
  ) async {
    await pumpApp(tester);
    for (final label in [
      'Open file',
      'Save file',
      'Clear',
      'Clients',
      'Execute',
    ]) {
      final control = find.text(label);
      expect(control.hitTestable(), findsOneWidget, reason: label);
      final rect = tester.getRect(control);
      expect(rect.left, greaterThanOrEqualTo(0), reason: label);
      expect(rect.top, greaterThanOrEqualTo(0), reason: label);
      expect(rect.right, lessThanOrEqualTo(860), reason: label);
      expect(rect.bottom, lessThanOrEqualTo(600), reason: label);
    }
    expect(find.text('New'), findsNothing);
    expect(find.byTooltip('New script').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('script folder lists files independently from editor tabs', (
    tester,
  ) async {
    late String alphaPath;
    await tester.runAsync(() async {
      alphaPath = (await controller.scriptLibrary!.createScript(
        'alpha.luau',
        content: 'print("alpha")',
      )).path;
      await controller.scriptLibrary!.createScript('beta.luau');
    });
    controller.newDocument(name: 'tab-only.luau', content: 'print("draft")');
    await pumpApp(tester);
    final explorer = find.byKey(const ValueKey('script-explorer'));
    Finder explorerLabel(String name) =>
        find.descendant(of: explorer, matching: find.text(name));
    expect(explorerLabel('alpha.luau'), findsOneWidget);
    expect(explorerLabel('beta.luau'), findsOneWidget);
    expect(explorerLabel('tab-only.luau'), findsNothing);
    expect(find.byKey(const ValueKey('script-folder:Special')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('script-file:Special/Orion Bridge.lua')),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(of: explorer, matching: find.byType(TextField)),
      'ALPHA',
    );
    await tester.pumpAndSettle();
    expect(explorerLabel('alpha.luau'), findsOneWidget);
    expect(explorerLabel('beta.luau'), findsNothing);
    expect(controller.documents, hasLength(2));
    expect(controller.activeDocument.name, 'tab-only.luau');

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('script-file:alpha.luau')));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    expect(controller.activeDocument.filePath, alphaPath);
    expect(controller.activeDocument.content, 'print("alpha")');
    controller.closeDocument(controller.activeDocumentId);
    await tester.pumpAndSettle();
    expect(explorerLabel('alpha.luau'), findsOneWidget);

    await tester.tap(find.byTooltip('New script'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.documents, hasLength(3));
    expect(controller.activeDocument.content, isEmpty);
    expect(find.byKey(const ValueKey('code-editor')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clear confirms before removing editor contents', (tester) async {
    final contents = controller.activeDocument.content;
    await pumpApp(tester);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Clear script?'), findsOneWidget);
    expect(controller.activeDocument.content, contents);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.activeDocument.content, contents);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Clear'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.activeDocument.content, isEmpty);
    expect(controller.activeDocument.isDirty, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    final clearButton = tester.widget<TextButton>(
      find
          .ancestor(of: find.text('Clear'), matching: find.byType(TextButton))
          .first,
    );
    expect(clearButton.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Open file and Save file route to the supplied file callbacks', (
    tester,
  ) async {
    var opened = 0;
    var saved = 0;
    cleanUp(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: orionTheme(Brightness.dark, controller.accentColor),
        home: Scaffold(
          body: WorkspaceScreen(
            controller: controller,
            onLibrary: () {},
            onOpen: () => opened++,
            onSave: () => saved++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open file'));
    await tester.tap(find.text('Save file'));
    expect(opened, 1);
    expect(saved, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'press feedback keeps editor bounds fixed and respects reduced motion',
    (tester) async {
      // Isolate the finite press animation from Special's independent loop.
      await tester.runAsync(() async {
        await Directory(
          '${controller.scriptLibrary!.directory.path}/Special',
        ).delete(recursive: true);
        await controller.scriptLibrary!.refresh();
      });
      controller.setReducedMotion(false);
      await pumpApp(tester);
      final button = find
          .ancestor(
            of: find.text('Open file'),
            matching: find.byType(TextButton),
          )
          .first;
      final feedback = find
          .ancestor(of: button, matching: find.byType(SpringPressFeedback))
          .first;
      final editor = find.byKey(const ValueKey('code-editor'));
      final buttonBounds = tester.getRect(feedback);
      final editorBounds = tester.getRect(editor);
      double scale() => tester
          .widget<Transform>(
            find
                .descendant(of: feedback, matching: find.byType(Transform))
                .first,
          )
          .transform
          .entry(0, 0);

      final press = await tester.startGesture(tester.getCenter(button));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(scale(), lessThan(1));
      expect(tester.getRect(feedback), buttonBounds);
      expect(tester.getRect(editor), editorBounds);
      await press.cancel();
      await tester.pumpAndSettle();
      expect(scale(), closeTo(1, .0001));
      expect(tester.binding.transientCallbackCount, 0);

      controller.setReducedMotion(true);
      await tester.pumpAndSettle();
      final still = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 70));
      expect(scale(), 1);
      expect(tester.getRect(editor), editorBounds);
      await still.cancel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

// These interaction checks exercise callbacks and state, with no disk writes
// scheduled inside Flutter's fake asynchronous event loop.
class _ActionController extends OrionController {
  _ActionController({required Directory storageDirectory})
    : super(storageDirectory: storageDirectory, persistChanges: false);

  @override
  Future<void> flushPersistence() async {}
}
