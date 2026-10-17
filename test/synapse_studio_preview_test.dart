import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart' show OrionShell;
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/synapse_studio_theme.dart';
import 'package:orion/services/synapse_theme_catalog.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/synapse_x/synapse_x_shell.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/synapse_studio_preview.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

void main() {
  setUpAll(() async {
    for (final font in const [
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Regular.ttf'),
      ('SynapseXUI', 'assets/synapse_x/fonts/Cantarell-Regular.otf'),
      ('SynapseXMono', 'assets/synapse_x/fonts/LiberationMono-Regular.ttf'),
      ('JetBrainsMono', 'assets/fonts/JetBrainsMono.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  late OrionController controller;
  late SynapseStudioTheme document;
  late String? selected;
  late double zoom;
  late int moveStarts;
  late int moveUpdates;
  late List<Size> resized;
  late StateSetter update;

  setUp(() {
    controller = OrionController(persistChanges: false)..setReducedMotion(true);
    document = SynapseThemeCatalog.defaults(InterfacePreset.synapseX)
        .withElement(
          'main',
          'editor',
          SynapseStudioElement(width: 120, height: 70),
        );
    selected = 'editor';
    zoom = 1;
    moveStarts = 0;
    moveUpdates = 0;
    resized = [];
  });
  tearDown(() => controller.dispose());

  Future<void> mount(
    WidgetTester tester, {
    double guiScale = 1,
    double sourceScale = 1,
    InterfacePreset preset = InterfacePreset.synapseX,
    bool resize = true,
  }) async {
    controller.setUiScale(sourceScale);
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: orionTheme(Brightness.dark, controller.accentColor),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 760,
              height: 480,
              child: UiScaleViewport(
                scale: guiScale,
                child: StatefulBuilder(
                  builder: (_, setState) {
                    update = setState;
                    return SynapseStudioPreview(
                      controller: controller,
                      preset: preset,
                      theme: document,
                      window: SynapseThemeCatalog.windows(preset).first,
                      selected: selected,
                      zoom: zoom,
                      onSelect: (id) => setState(() => selected = id),
                      onMoveStart: () => moveStarts++,
                      onMove: (id, delta) => setState(() {
                        moveUpdates++;
                        final current = document.window('main').elements[id]!;
                        document = document.withElement(
                          'main',
                          id,
                          current.copyWith(
                            x: current.x + delta.dx,
                            y: current.y + delta.dy,
                          ),
                        );
                      }),
                      onResize: !resize
                          ? null
                          : (id, size) => setState(() {
                              resized.add(size);
                              document = document.withElement(
                                'main',
                                id,
                                document
                                    .window('main')
                                    .elements[id]!
                                    .copyWith(
                                      width: size.width,
                                      height: size.height,
                                    ),
                              );
                            }),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'selection chrome preserves measured bounds and other layer taps',
    (tester) async {
      selected = 'content';
      await mount(tester, resize: false);
      final surface = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('studio-canvas-surface')),
      );
      expect(
        (surface.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(24),
      );
      expect(
        find.byKey(const ValueKey('studio-preview-resize:content')),
        findsNothing,
      );
      final handle = find.byKey(const ValueKey('studio-preview:editor'));
      final before = tester.getRect(handle);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(before.center);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('studio-preview-hover:editor')),
        findsOneWidget,
      );
      await tester.tapAt(before.center);
      await tester.pumpAndSettle();
      expect(selected, 'editor');
      expect(
        find.byKey(const ValueKey('studio-preview-selection:editor')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('studio-preview-move:editor')),
        findsOneWidget,
      );
      expect(tester.getRect(handle), before);
      expect(document.window('main').elements['editor']!.width, 120);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final settings in [
    (1.0, 1.0, 1.0),
    (.75, 1.25, 1.0),
    (1.0, 1.25, 1.25),
    (.8, .8, .8),
  ]) {
    testWidgets(
      'resize follows source coordinates at zoom ${settings.$1} Studio GUI ${settings.$2} source GUI ${settings.$3}',
      (tester) async {
        zoom = settings.$1;
        await mount(tester, guiScale: settings.$2, sourceScale: settings.$3);
        final editor = find.byKey(const ValueKey('studio-preview:editor'));
        final ratio = tester.getRect(editor).width / 120;
        final handle = find.byKey(
          const ValueKey('studio-preview-resize:editor'),
        );
        expect(tester.getRect(handle).width, closeTo(24 * settings.$2, .05));
        final resize = await tester.startGesture(tester.getCenter(handle));
        await resize.moveBy(const Offset(30, 15));
        await tester.pumpAndSettle();
        await resize.moveBy(const Offset(30, 15));
        await tester.pumpAndSettle();
        await resize.up();
        await tester.pumpAndSettle();
        expect(moveStarts, 1);
        expect(moveUpdates, 0);
        expect(resized.last.width, closeTo(120 + 60 / ratio, .05));
        expect(resized.last.height, closeTo(70 + 30 / ratio, .05));
        final actual = tester.getRect(editor);
        expect(actual.width, closeTo(resized.last.width * ratio, .05));
        expect(actual.height, closeTo(resized.last.height * ratio, .05));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('source viewport and drags are independent of Studio scaling', (
    tester,
  ) async {
    await mount(tester, guiScale: .8, sourceScale: 1.25);
    final context = tester.element(find.byType(SynapseXShell));
    final media = MediaQuery.of(context);
    expect(media.size, const Size(801, 355) / 1.25);
    expect(media.padding, EdgeInsets.zero);
    expect(media.viewInsets, EdgeInsets.zero);
    final editor = find.byKey(const ValueKey('studio-preview:editor'));
    final before = tester.getRect(editor);
    final ratio = before.width / 120;
    await tester.drag(editor, const Offset(30, 15));
    await tester.pumpAndSettle();
    expect(
      document.window('main').elements['editor']!.x,
      closeTo(30 / ratio, .05),
    );
    expect(
      document.window('main').elements['editor']!.y,
      closeTo(15 / ratio, .05),
    );
    final after = tester.getRect(editor);
    expect(after.topLeft - before.topLeft, const Offset(30, 15));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('canvas excludes runtime output without clearing the owner', (
    tester,
  ) async {
    controller.applyWindowState({
      ...controller.exportWindowState(),
      'activities': [
        {
          'id': 'private-runtime-output',
          'title': 'Live client',
          'detail': 'Runtime console marker',
          'kind': 'execution',
          'severity': 'error',
          'timestamp': '2026-10-16T10:00:00.000Z',
        },
      ],
    });
    await mount(tester);
    final source = tester.widget<SynapseXShell>(find.byType(SynapseXShell));
    expect(
      source.controller.activities.where(
        (entry) => entry.id == 'private-runtime-output',
      ),
      isEmpty,
    );
    expect(controller.activities.single.id, 'private-runtime-output');
    expect(find.text('Runtime console marker'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('open Orion canvas follows size modes and GUI changes', (
    tester,
  ) async {
    document = SynapseThemeCatalog.defaults(InterfacePreset.orion);
    selected = null;
    await mount(tester, preset: InterfacePreset.orion);
    final source = find.byType(OrionShell);
    expect(MediaQuery.sizeOf(tester.element(source)), const Size(822, 523));
    controller.setOrionCompactMode(true);
    update(() {});
    await tester.pumpAndSettle();
    expect(MediaQuery.sizeOf(tester.element(source)), const Size(740, 470));
    controller.setUiScale(1.25);
    update(() {});
    await tester.pumpAndSettle();
    expect(
      MediaQuery.sizeOf(tester.element(source)),
      const Size(740, 470) / 1.25,
    );
    expect(
      tester.widget<OrionShell>(source).controller.orionCompactMode,
      isTrue,
    );
    controller.setOrionEnlargedMode(true);
    update(() {});
    await tester.pumpAndSettle();
    expect(
      MediaQuery.sizeOf(tester.element(source)),
      const Size(1045, 648) / 1.25,
    );
    expect(
      tester.widget<OrionShell>(source).controller.orionEnlargedMode,
      isTrue,
    );
    expect(
      tester.widget<OrionShell>(source).controller.orionCompactMode,
      isFalse,
    );
    controller.setOrionEnlargedMode(false);
    update(() {});
    await tester.pumpAndSettle();
    expect(
      MediaQuery.sizeOf(tester.element(source)),
      const Size(822, 523) / 1.25,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'middle drag pans zoomed source without editing and Fit recenters',
    (tester) async {
      zoom = 2;
      await mount(tester, guiScale: 1.25);
      final source = find.byType(SynapseXShell);
      final before = tester.getRect(source);
      final canvas = tester.getRect(
        find.byKey(const ValueKey('studio-preview-canvas')),
      );
      final gesture = await tester.startGesture(
        canvas.center,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await gesture.moveBy(const Offset(80, 20));
      await tester.pumpAndSettle();
      await gesture.up();
      final after = tester.getRect(source);
      expect(after.left - before.left, closeTo(80, .05));
      expect(after.top - before.top, closeTo(20, .05));
      expect(moveStarts, 0);
      expect(moveUpdates, 0);
      expect(resized, isEmpty);
      expect(document.window('main').elements['editor']!.x, 0);
      final limits = await tester.startGesture(
        canvas.center,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await limits.moveBy(const Offset(4000, 4000));
      await tester.pumpAndSettle();
      expect(tester.getRect(source).left, closeTo(canvas.left + 30, .05));
      expect(tester.getRect(source).top, closeTo(canvas.top + 30, .05));
      await limits.moveBy(const Offset(-8000, -8000));
      await tester.pumpAndSettle();
      expect(tester.getRect(source).right, closeTo(canvas.right - 30, .05));
      expect(tester.getRect(source).bottom, closeTo(canvas.bottom - 30, .05));
      await limits.up();
      expect(
        find.byKey(const ValueKey('studio-canvas-pan-hint')),
        findsOneWidget,
      );
      update(() => zoom = 1);
      await tester.pumpAndSettle();
      expect(tester.getRect(source).center, canvas.center);
      expect(
        find.byKey(const ValueKey('studio-canvas-pan-hint')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'empty canvas pans while direct element dragging only edits the layer',
    (tester) async {
      zoom = 1.35;
      await mount(tester);
      final canvas = tester.getRect(
        find.byKey(const ValueKey('studio-preview-canvas')),
      );
      final source = find.byType(SynapseXShell);
      final before = tester.getRect(source);
      final blank = Offset(canvas.center.dx, canvas.top + 5);
      final pan = await tester.startGesture(blank);
      await pan.moveBy(const Offset(60, 0));
      await tester.pumpAndSettle();
      await pan.up();
      final panned = tester.getRect(source);
      expect(panned.left, greaterThan(before.left));
      expect(moveStarts, 0);
      final editor = find.byKey(const ValueKey('studio-preview:editor'));
      await tester.drag(editor, const Offset(40, 10));
      await tester.pumpAndSettle();
      expect(moveStarts, 1);
      expect(moveUpdates, greaterThan(0));
      expect(document.window('main').elements['editor']!.x, greaterThan(0));
      expect(tester.getRect(source), panned);
      await tester.tapAt(blank);
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
