import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart';
import 'package:orion/state/orion_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in const [
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Regular.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Medium.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Semibold.ttf'),
      ('JetBrainsMono', 'assets/fonts/JetBrainsMono.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(font.$1)..addFont(rootBundle.load(font.$2));
      await loader.load();
    }
  });

  for (final size in [const Size(720, 480), const Size(822, 523)]) {
    testWidgets(
      'slider scales navigation, dialogs and retained drafts at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = _MemoryController()
          ..setReducedMotion(true)
          ..completeIntro();
        final draftId = controller.activeDocumentId;
        controller.renameDocument(draftId, 'draft.luau');
        controller.newDocument(name: 'second.luau', content: 'print("second")');
        controller.selectDocument(draftId);
        try {
          await tester.pumpWidget(
            OrionApp(controller: controller, nativeWindow: false),
          );
          await _settle(tester);
          const draft = '-- retain the actual edited draft\nlocal answer = 42';
          final editor = find.byKey(const ValueKey('code-editor'));
          await tester.enterText(editor, draft);
          await _settle(tester);

          for (final scale in [.8, 1.0, 1.25]) {
            await tester.tap(find.byTooltip('Theme Control'));
            await _settle(tester);
            final slider = find.byKey(const ValueKey('ui-scale-slider'));
            if (slider.evaluate().isEmpty) {
              await tester.ensureVisible(
                find.byKey(const ValueKey('theme-layout-controls')),
              );
              await _settle(tester);
              await tester.tap(find.text('Layout & motion'));
              await _settle(tester);
            }
            await tester.ensureVisible(slider);
            await _settle(tester);
            final box = tester.renderObject<RenderBox>(slider);
            final fraction = (scale - .8) / .45;
            final x = (box.size.width * fraction).clamp(
              2.0,
              box.size.width - 2,
            );
            await tester.tapAt(
              box.localToGlobal(Offset(x, box.size.height / 2)),
            );
            await _settle(tester);
            expect(controller.uiScale, scale);
            expect(
              tester.takeException(),
              isNull,
              reason: '$scale settings at $size',
            );

            for (final destination in ['Scripts', 'UI Selection', 'Editor']) {
              await tester.tap(find.byTooltip(destination));
              await _settle(tester);
              expect(
                tester.takeException(),
                isNull,
                reason: '$scale $destination at $size',
              );
            }
            expect(controller.documents, hasLength(2));
            expect(controller.activeDocument.id, draftId);
            expect(tester.widget<TextField>(editor).controller!.text, draft);
            final execute = find.widgetWithText(FilledButton, 'Execute');
            expect(execute.hitTestable(), findsOneWidget);
            expect(
              _paintRect(tester, execute).height,
              closeTo(36 * scale, .01),
            );

            await _selectTab(
              tester,
              'second.luau',
              revealWith: 'Scroll tabs right',
            );
            await _settle(tester);
            expect(
              tester.widget<TextField>(editor).controller!.text,
              'print("second")',
            );
            await _selectTab(
              tester,
              'draft.luau',
              revealWith: 'Scroll tabs left',
            );
            await _settle(tester);
            expect(tester.widget<TextField>(editor).controller!.text, draft);
            expect(controller.activeDocument.isDirty, isTrue);

            await tester.tap(find.byTooltip('Editor actions'));
            await _settle(tester);
            expect(find.text('Save as…'), findsOneWidget);
            final menu = find.byKey(const ValueKey('orion-popup-menu'));
            expect(menu, findsOneWidget);
            final menuRect = _paintRect(tester, menu);
            expect(menuRect.left, greaterThanOrEqualTo(0));
            expect(menuRect.top, greaterThanOrEqualTo(0));
            expect(menuRect.right, lessThanOrEqualTo(size.width));
            expect(menuRect.bottom, lessThanOrEqualTo(size.height));
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await _settle(tester);

            await tester.tap(find.byTooltip('Clear script'));
            await _settle(tester);
            final dialog = find.byType(AlertDialog);
            expect(dialog, findsOneWidget);
            final rect = _paintRect(tester, dialog);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
            expect(rect.bottom, lessThanOrEqualTo(size.height));
            expect(find.text('Cancel').hitTestable(), findsOneWidget);
            await tester.tap(find.text('Cancel'));
            await _settle(tester);
            expect(controller.activeDocument.content, draft);
            expect(
              tester.takeException(),
              isNull,
              reason: '$scale modal at $size',
            );
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );
  }
}

Finder _tab(String label) => find.descendant(
  of: find.byKey(const ValueKey('workspace-editor-panel')),
  matching: find.text(label),
);

Future<void> _selectTab(
  WidgetTester tester,
  String label, {
  required String revealWith,
}) async {
  final target = _tab(label);
  // A selected tab is revealed automatically. At large GUI scales that can
  // legitimately scroll the other tab outside the clipped viewport.
  for (
    var attempt = 0;
    target.hitTestable().evaluate().isEmpty && attempt < 10;
    attempt++
  ) {
    final cue = find.byTooltip(revealWith);
    expect(cue, findsOneWidget);
    final button = find.ancestor(of: cue, matching: find.byType(IconButton));
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    await tester.tap(cue);
    await _settle(tester);
  }
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target.hitTestable());
}

Rect _paintRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

class _MemoryController extends OrionController {
  @override
  Future<void> flushPersistence() async {}
}
