import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';

void main() {
  late _MenuController c;
  late String alpha, beta;

  setUp(() {
    c = _MenuController()
      ..setReducedMotion(true)
      ..completeIntro();
    final initial = c.activeDocumentId;
    alpha = c.newDocument(name: 'alpha.lua', content: 'print("alpha")').id;
    beta = c.newDocument(name: 'beta.lua', content: 'print("beta")').id;
    c.closeDocument(initial);
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(822, 523);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      c.dispose();
    });
    await tester.pumpWidget(OrionApp(controller: c, nativeWindow: false));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, String id) async {
    await tester.tap(
      find.byKey(ValueKey('workspace-tab:$id')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('orion-popup-menu')), findsOneWidget);
  }

  Finder getInput() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );

  testWidgets(
    'right-click renames the target without selecting or altering it',
    (tester) async {
      await mount(tester);
      final before = c.documents.firstWhere((doc) => doc.id == alpha);
      await open(tester, alpha);
      expect(c.activeDocumentId, beta);
      for (final label in ['Rename tab', 'Save', 'Save as…', 'Close tab']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Rename tab'));
      await tester.pumpAndSettle();
      final input = getInput();
      final editing = tester.widget<TextField>(input).controller!;
      expect(editing.selection.textInside(editing.text), 'alpha');
      await tester.enterText(input, '  renamed.lua  ');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      final after = c.documents.firstWhere((doc) => doc.id == alpha);
      expect(after.name, 'renamed.lua');
      expect(after.content, before.content);
      expect(after.savedContent, before.savedContent);
      expect(after.filePath, before.filePath);
      expect(after.isDirty, before.isDirty);
      expect(c.activeDocumentId, beta);
      expect(find.text('renamed.lua'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty rename stays open and cancel preserves the name', (
    tester,
  ) async {
    await mount(tester);
    await open(tester, beta);
    await tester.tap(find.text('Rename tab'));
    await tester.pumpAndSettle();
    await tester.enterText(getInput(), '   ');
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Rename'),
    );
    expect(button.onPressed, isNull);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(c.activeDocument.name, 'beta.lua');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.activeDocument.name, 'beta.lua');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Save and Save as address the clicked inactive document', (
    tester,
  ) async {
    await mount(tester);
    await open(tester, alpha);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.saved, [alpha]);
    expect(c.activeDocumentId, beta);
    await open(tester, alpha);
    await tester.tap(find.text('Save as…'));
    await tester.pumpAndSettle();
    expect(c.savedAs, [alpha]);
    expect(c.activeDocumentId, beta);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Close keeps unsaved confirmation and targets only clicked tab', (
    tester,
  ) async {
    c.updateDocumentContent(alpha, 'print("unsaved alpha")');
    await mount(tester);
    await open(tester, alpha);
    await tester.tap(find.text('Close tab'));
    await tester.pumpAndSettle();
    expect(find.text('alpha.lua has unsaved changes.'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(c.documents, hasLength(2));
    await open(tester, alpha);
    await tester.tap(find.text('Close tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(c.documents.single.id, beta);
    expect(c.activeDocumentId, beta);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab context menu follows all main themes and dismisses safely', (
    tester,
  ) async {
    await mount(tester);
    for (final preset in OrionThemePreferences.builtInPresets.take(5)) {
      c.setOrionTheme(preset.preferences.copyWith(rainEnabled: false));
      await tester.pumpAndSettle();
      await open(tester, beta);
      final menu = tester.element(
        find.byKey(const ValueKey('orion-popup-menu')),
      );
      final page = tester.element(find.byKey(ValueKey('workspace-tab:$beta')));
      expect(OrionColors.of(menu).accent, OrionColors.of(page).accent);
      final rect = tester.getRect(
        find.byKey(const ValueKey('orion-popup-menu')),
      );
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(822));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('orion-popup-menu')), findsNothing);
      expect(c.activeDocumentId, beta);
      expect(c.documents, hasLength(2));
      expect(tester.takeException(), isNull);
    }
  });
}

class _MenuController extends OrionController {
  _MenuController() : super(persistChanges: false);
  final saved = <String?>[], savedAs = <String?>[];

  @override
  Future<bool> saveDocument([String? id]) async {
    saved.add(id);
    return false;
  }

  @override
  Future<bool> saveAs([String? id]) async {
    savedAs.add(id);
    return false;
  }
}
