import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/screens/workspace_screen.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/expressive_motion.dart';
import 'package:orion/theme/orion_density.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

class _MemoryController extends OrionController {
  @override
  Future<void> flushPersistence() async {}
}

ThemeData _theme(OrionController controller, OrionDensity density) {
  final theme = orionTheme(Brightness.dark, controller.accentColor);
  return theme.copyWith(extensions: [...theme.extensions.values, density]);
}

void main() {
  setUpAll(() async {
    for (final font in const [
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Regular.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Medium.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Semibold.ttf'),
      ('JetBrainsMono', 'assets/fonts/JetBrainsMono.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  Future<void> pumpWorkspace(
    WidgetTester tester,
    OrionController controller, {
    required Size size,
    double scale = 1,
    ValueNotifier<OrionDensity>? density,
    VoidCallback? onOpen,
    VoidCallback? onSave,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(controller.dispose);
    final value = density ?? ValueNotifier(OrionDensity.compact);
    if (density == null) addTearDown(value.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<OrionDensity>(
        valueListenable: value,
        builder: (context, density, _) => MaterialApp(
          theme: _theme(controller, density),
          themeAnimationDuration: controller.reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 480),
          themeAnimationCurve: OrionMotion.spatial,
          builder: (context, child) =>
              UiScaleViewport(scale: scale, child: child!),
          home: Scaffold(
            body: Padding(
              // Reserve the compact shell's rail, header and outer gutter.
              padding: const EdgeInsets.fromLTRB(76, 50, 8, 8),
              child: WorkspaceScreen(
                controller: controller,
                onLibrary: () {},
                onOpen: onOpen ?? () {},
                onSave: onSave ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(740, 470), Size(680, 420)]) {
    for (final scale in const [.8, 1.0, 1.25]) {
      testWidgets(
        'compact workspace retains actions and an editable draft at $size / $scale',
        (tester) async {
          final controller = _MemoryController()
            ..setReducedMotion(true)
            ..setUiScale(scale)
            ..setEditorFontSize(18);
          const draft = 'print("Hello world")\n-- unsaved';
          controller.updateDocumentContent(controller.activeDocumentId, draft);
          var opened = 0;
          var saved = 0;
          await pumpWorkspace(
            tester,
            controller,
            size: size,
            scale: scale,
            onOpen: () => opened++,
            onSave: () => saved++,
          );
          for (final label in ['Execute']) {
            final action = find.text(label).hitTestable();
            expect(action, findsOneWidget, reason: label);
            final rect = tester.getRect(action);
            expect(rect.left, greaterThanOrEqualTo(0), reason: label);
            expect(rect.right, lessThanOrEqualTo(size.width), reason: label);
            expect(rect.bottom, lessThanOrEqualTo(size.height), reason: label);
          }
          expect(find.byTooltip('Open file · Ctrl O'), findsOneWidget);
          expect(find.byTooltip('Save file · Ctrl S'), findsOneWidget);
          expect(find.byTooltip('Clear script').hitTestable(), findsOneWidget);
          expect(find.byTooltip('Clients').hitTestable(), findsOneWidget);
          final explorer = find.byKey(const ValueKey('script-explorer'));
          expect(explorer, findsOneWidget);
          expect(tester.getSize(explorer).width, inInclusiveRange(120, 168));
          await tester.tap(find.byTooltip('Open file · Ctrl O'));
          await tester.tap(find.byTooltip('Save file · Ctrl S'));
          expect(opened, 1);
          expect(saved, 1);
          final editor = find.byKey(const ValueKey('code-editor'));
          expect(tester.widget<TextField>(editor).style!.fontSize, 18);
          expect(
            tester.getSize(find.byKey(const ValueKey('editor-body'))).height,
            greaterThan(60),
          );
          expect(controller.activeDocument.content, draft);
          expect(controller.activeDocument.isDirty, isTrue);

          await tester.tap(find.byTooltip('New script'));
          await tester.pumpAndSettle();
          expect(controller.documents, hasLength(2));
          await tester.enterText(editor, 'print("compact")');
          expect(controller.activeDocument.content, 'print("compact")');
          expect(controller.documents.first.content, draft);
          await tester.tap(find.text('Console'));
          await tester.pumpAndSettle();
          expect(
            tester.getSize(find.byKey(const ValueKey('editor-body'))).height,
            greaterThan(20),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('density morphs editor chrome while keeping its text and draft', (
    tester,
  ) async {
    final controller = _MemoryController()..setEditorFontSize(17);
    const draft = 'print("Hello world")';
    controller.updateDocumentContent(controller.activeDocumentId, draft);
    final density = ValueNotifier(OrionDensity.comfortable);
    addTearDown(density.dispose);
    await pumpWorkspace(
      tester,
      controller,
      size: const Size(900, 600),
      density: density,
    );
    final explorer = find.byKey(const ValueKey('script-explorer'));
    final editor = find.byKey(const ValueKey('editor-body'));
    final width = tester.getSize(explorer).width;
    final height = tester.getSize(editor).height;
    density.value = OrionDensity.compact;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final intermediate = tester.getSize(explorer).width;
    expect(intermediate, lessThan(width));
    expect(intermediate, greaterThan(148));
    await tester.pumpAndSettle();
    expect(tester.getSize(explorer).width, closeTo(148, .01));
    expect(tester.getSize(editor).height, greaterThan(height));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('code-editor')))
          .style!
          .fontSize,
      17,
    );
    expect(controller.activeDocument.content, draft);
    expect(controller.activeDocument.isDirty, isTrue);

    density.value = OrionDensity.comfortable;
    await tester.pumpAndSettle();
    expect(tester.getSize(explorer).width, closeTo(width, .01));
    expect(tester.getSize(editor).height, closeTo(height, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('comfortable density is retained outside Orion', (tester) async {
    final controller = _MemoryController()
      ..setReducedMotion(true)
      ..setInterface(InterfacePreset.rc7);
    await pumpWorkspace(tester, controller, size: const Size(900, 600));
    expect(find.text('Open file'), findsOneWidget);
    expect(find.text('Save file'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
