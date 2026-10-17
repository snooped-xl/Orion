import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/screens/theme_control_screen.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = FontLoader('RobotoFlex')
      ..addFont(rootBundle.load('assets/fonts/RobotoFlex-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/RobotoFlex-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/RobotoFlex-Semibold.ttf'));
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test(
    'UI scale uses five-percent steps and preserves edits and editor font',
    () {
      final controller = OrionController();
      addTearDown(controller.dispose);
      expect(controller.uiScale, 1.0);
      final document = controller.newDocument(
        name: 'scale.lua',
        content: '-- saved',
      );
      controller.updateDocumentContent(document.id, 'print("keep this edit")');
      controller.setEditorFontSize(18);
      for (final option in const [
        (.824, .8),
        (.826, .85),
        (1.079, 1.1),
        (1.234, 1.25),
        (.3, .8),
        (2.0, 1.25),
      ]) {
        controller.setUiScale(option.$1);
        expect(controller.uiScale, option.$2);
        expect(controller.activeDocument.id, document.id);
        expect(controller.activeDocument.content, 'print("keep this edit")');
        expect(controller.activeDocument.isDirty, isTrue);
        expect(controller.editorFontSize, 18);
      }
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        controller.setUiScale(value);
        expect(controller.uiScale, 1.0);
      }
      var changes = 0;
      controller.addListener(() => changes++);
      controller.setUiScale(1.01);
      expect(changes, 0);
      controller.setUiScale(1.1);
      expect(changes, 1);
    },
  );

  test('UI scale persists independently from the editor font', () async {
    final directory = Directory.systemTemp.createTempSync('orion-ui-scale-');
    final controller = OrionController(storageDirectory: directory);
    OrionController? restored;
    try {
      await controller.initialize();
      controller.setUiScale(1.15);
      controller.setEditorFontSize(19);
      await controller.flushPersistence();
      final saved =
          jsonDecode(
                await File(
                  '${directory.path}/orion-workspace.json',
                ).readAsString(),
              )
              as Map;
      expect(saved['uiScale'], 1.15);
      expect(saved['editorFontSize'], 19);
      restored = OrionController(storageDirectory: directory);
      await restored.initialize();
      expect(restored.uiScale, 1.15);
      expect(restored.editorFontSize, 19);
    } finally {
      controller.dispose();
      await controller.flushPersistence();
      restored?.dispose();
      if (restored != null) await restored.flushPersistence();
      await directory.delete(recursive: true);
    }
  });

  test(
    'stored UI scale handles missing, invalid, nonfinite and extreme values',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'orion-ui-scale-restore-',
      );
      try {
        final state = File('${directory.path}/orion-workspace.json');
        for (final option in const [
          ('{}', 1.0),
          ('{"uiScale":null}', 1.0),
          ('{"uiScale":"NaN"}', 1.0),
          ('{"uiScale":true}', 1.0),
          ('{"uiScale":1e999}', 1.0),
          ('{"uiScale":-1e999}', 1.0),
          ('{"uiScale":0.2}', .8),
          ('{"uiScale":20}', 1.25),
          ('{"uiScale":1.079}', 1.1),
        ]) {
          await state.writeAsString(option.$1);
          final controller = OrionController(storageDirectory: directory);
          try {
            await controller.initialize();
            expect(controller.uiScale, option.$2, reason: option.$1);
            await controller.flushPersistence();
            expect(controller.persistenceError, isNull);
          } finally {
            controller.dispose();
            await controller.flushPersistence();
          }
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'Theme Control UI scale previews a drag without changing the editor font',
    (tester) async {
      final controller = OrionController()..setReducedMotion(true);
      addTearDown(controller.dispose);
      await _mount(tester, controller, const Size(1080, 720));
      final scale = find.byKey(const ValueKey('ui-scale-slider'));
      expect(find.text('UI scale'), findsOneWidget);
      expect(find.text('100%'), findsWidgets);
      expect(controller.editorFontSize, 14);
      final slider = tester.widget<Slider>(scale);
      expect(slider.divisions, 9);
      expect(slider.semanticFormatterCallback!(1.1), 'UI scale, 110 percent');
      final start = tester.getCenter(scale);
      final gesture = await tester.startGesture(start);
      await tester.pump();
      await gesture.moveTo(start + const Offset(400, 0));
      await tester.pump();
      expect(
        controller.uiScale,
        1.0,
        reason: 'Dragging previews without moving the global viewport',
      );
      expect(find.text('125%'), findsOneWidget);
      expect(tester.widget<Slider>(scale).value, 1.25);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.uiScale, 1.25);
      expect(find.text('125%'), findsOneWidget);
      expect(controller.editorFontSize, 14);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.flushPersistence();
    },
  );

  testWidgets(
    'UI scale keyboard and accessibility changes commit immediately',
    (tester) async {
      final controller = OrionController()..setReducedMotion(true);
      addTearDown(controller.dispose);
      final semantics = tester.ensureSemantics();
      await _mount(tester, controller, const Size(1080, 720));
      final scale = find.byKey(const ValueKey('ui-scale-slider'));
      tester.widget<Slider>(scale).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controller.uiScale, 1.05);
      expect(find.text('105%'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(controller.uiScale, 1.0);
      SemanticsNode? scaleNode;
      void findScaleNode(SemanticsNode node) {
        final data = node.getSemanticsData();
        if (data.value.startsWith('UI scale,') &&
            data.hasAction(SemanticsAction.increase)) {
          scaleNode = node;
        }
        node.visitChildren((child) {
          findScaleNode(child);
          return true;
        });
      }

      findScaleNode(tester.getSemantics(scale));
      expect(scaleNode, isNotNull);
      scaleNode!.owner!.performAction(scaleNode!.id, SemanticsAction.increase);
      await tester.pump();
      expect(controller.uiScale, 1.05);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.flushPersistence();
      semantics.dispose();
    },
  );

  testWidgets('UI scale midpoint remains visible in a 473px logical viewport', (
    tester,
  ) async {
    final controller = OrionController()
      ..setReducedMotion(true)
      ..setUiScale(1.05);
    addTearDown(controller.dispose);
    await _mount(tester, controller, const Size(473, 384));
    expect(find.text('105%').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ui-scale-slider')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.flushPersistence();
  });
}

Future<void> _mount(
  WidgetTester tester,
  OrionController controller,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await controller.flushPersistence();
  await tester.pumpWidget(
    MaterialApp(
      theme: orionTheme(Brightness.dark, controller.accentColor),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(10),
          child: ThemeControlScreen(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final layout = find.byKey(const ValueKey('theme-layout-controls'));
  await tester.ensureVisible(layout);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Layout & motion'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('ui-scale-slider')));
  await tester.pumpAndSettle();
}
