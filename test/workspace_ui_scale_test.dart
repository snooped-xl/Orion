import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/screens/workspace_screen.dart';

class _MemoryController extends OrionController {
  _MemoryController() : super(useMacSploit: false);

  @override
  Future<void> flushPersistence() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in const [
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Regular.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Medium.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Semibold.ttf'),
      ('JetBrainsMono', 'assets/fonts/JetBrainsMono.ttf'),
      ('SynapseInter', 'assets/synapse_v3/fonts/Inter-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(font.$1)..addFont(rootBundle.load(font.$2));
      await loader.load();
    }
  });

  for (final compact in [false, true]) {
    for (final scale in [.8, 1.0, 1.25]) {
      testWidgets(
        'Scripts remains visible in ${compact ? 'compact' : 'normal'} minimum window at $scale GUI',
        (tester) async {
          final size = compact ? const Size(680, 420) : const Size(720, 480);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = _MemoryController()
            ..setReducedMotion(true)
            ..setUiScale(scale)
            ..setOrionCompactMode(compact)
            ..completeIntro();
          const draft = 'print("Scripts stays available")';
          controller.updateDocumentContent(controller.activeDocumentId, draft);
          try {
            await tester.pumpWidget(
              OrionApp(controller: controller, nativeWindow: false),
            );
            await tester.pumpAndSettle();
            final explorer = find.byKey(const ValueKey('script-explorer'));
            final workspace = find.byType(WorkspaceScreen);
            final editor = find.byKey(const ValueKey('editor-body'));
            expect(explorer, findsOneWidget);
            expect(
              find
                  .descendant(of: explorer, matching: find.text('Scripts'))
                  .hitTestable(),
              findsOneWidget,
            );
            final explorerRect = tester.getRect(explorer);
            expect(explorerRect.width / scale, inInclusiveRange(120, 168));
            expect(tester.getSize(editor).width, greaterThan(300));
            expect(tester.getSize(editor).height, greaterThan(40));
            expect(
              tester.getRect(workspace).contains(explorerRect.topLeft),
              isTrue,
            );
            expect(explorerRect.right, lessThan(size.width));
            for (final tooltip in [
              'Open file · Ctrl O',
              'Save file · Ctrl S',
              'Clear script',
              'Clients',
            ]) {
              expect(
                find.byTooltip(tooltip).hitTestable(),
                findsOneWidget,
                reason: tooltip,
              );
            }
            expect(find.text('Execute').hitTestable(), findsOneWidget);
            final editorState = tester.state(
              find.byKey(const ValueKey('code-editor')),
            );
            controller.setUiScale(scale == 1.25 ? 1 : 1.25);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('script-explorer')),
              findsOneWidget,
            );
            expect(
              tester.state(find.byKey(const ValueKey('code-editor'))),
              same(editorState),
            );
            expect(controller.activeDocument.content, draft);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
          }
        },
      );
    }
  }

  testWidgets('execution console fits every layout at maximum UI scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(720, 480);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _MemoryController()
      ..setUiScale(1.25)
      ..setReducedMotion(true)
      ..setEditorFontSize(22)
      ..completeIntro();
    const source = 'local value = 42\nprint(value)';
    controller.updateDocumentContent(controller.activeDocumentId, source);
    try {
      await tester.pumpWidget(
        OrionApp(controller: controller, nativeWindow: false),
      );
      await tester.pumpAndSettle();
      for (final preset in InterfacePreset.values) {
        // Blue/X/OG have source-sized companion console pages, covered by their
        // own viewport tests; this regression covers embedded editor consoles.
        if (preset.isStandalone && preset != InterfacePreset.synapseV3) {
          continue;
        }
        controller.setInterface(preset);
        if (preset == InterfacePreset.synapseV3) {
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
        }
        await tester.pumpAndSettle();
        final synapse = preset == InterfacePreset.synapseV3;
        final execute = synapse
            ? find.byTooltip('Execute script · Ctrl Enter')
            : find.widgetWithText(FilledButton, 'Execute');
        if (synapse) {
          expect(
            find
                .widgetWithText(TextButton, 'Execute')
                .evaluate()
                .every(
                  (element) => (element.widget as TextButton).onPressed == null,
                ),
            isTrue,
          );
          await tester.tap(find.byTooltip('Show console'));
          await tester.pumpAndSettle();
        } else {
          await tester.tap(execute);
          await tester.pumpAndSettle();
        }
        expect(find.text('Console'), findsOneWidget);
        expect(execute.hitTestable(), findsOneWidget);
        final editor = find.byKey(
          ValueKey(synapse ? 'v3-editor-body' : 'editor-body'),
        );
        expect(tester.getSize(editor).height, greaterThan(20));
        expect(controller.activeDocument.content, source);
        expect(tester.takeException(), isNull, reason: preset.label);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });
}
