import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:orion/app.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/widgets/bridge_client_manager.dart';
import 'package:orion/screens/ui_selection_screen.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/theme/orion_density.dart';
import 'package:orion/widgets/interface_logo.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

class _SourceClientController extends OrionController {
  _SourceClientController() : super(persistChanges: false, useMacSploit: false);
  String? executedSource;
  @override
  void execute({String? source, String? name}) {
    executedSource = source ?? activeDocument.content;
    super.execute(source: source, name: name);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final font in const [
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Regular.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Medium.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Semibold.ttf'),
      ('SynapseInter', 'assets/synapse_v3/fonts/Inter-Regular.ttf'),
      ('OriginalNunito', 'assets/original_zenith/Fonts/nunito-wght.ttf'),
      ('OriginalAwpUI', 'assets/original_awp/Inter-Regular.ttf'),
      ('OriginalAwpUI', 'assets/original_awp/Inter-SemiBold.ttf'),
      ('OriginalXenoUI', 'assets/original_xeno/NotoSans-Regular.ttf'),
      ('OriginalXenoUI', 'assets/original_xeno/NotoSans-Black.ttf'),
      ('OriginalArial', 'assets/original_fonts/LiberationSans-Regular.ttf'),
      ('OriginalSans', 'assets/original_fonts/LiberationSans-Regular.ttf'),
      ('OriginalSegoeUI', 'assets/synapse_x/fonts/Cantarell-Regular.otf'),
      ('OriginalConsolas', 'assets/synapse_x/fonts/LiberationMono-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(font.$1)..addFont(rootBundle.load(font.$2));
      await loader.load();
    }
  });

  testWidgets(
    'Glassy selector actions use the same rounded outline as their fill',
    (tester) async {
      final controller = OrionController(persistChanges: false)
        ..setReducedMotion(true);
      addTearDown(controller.dispose);
      for (final glassy in [false, true]) {
        final preferences = glassy
            ? OrionThemePreferences.builtInPresets[3].preferences
            : OrionThemePreferences.defaults;
        await tester.pumpWidget(
          MaterialApp(
            theme: orionTheme(
              Brightness.dark,
              preferences.accent,
              preferences: preferences,
              reducedMotion: true,
            ),
            home: Scaffold(body: UISelectionScreen(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();
        for (final preset in InterfacePresetDetails.available) {
          final material = tester.widget<Material>(
            find
                .descendant(
                  of: _select(preset),
                  matching: find.byType(Material),
                )
                .first,
          );
          final shape = material.shape! as RoundedRectangleBorder;
          expect(
            shape.borderRadius,
            glassy
                ? BorderRadius.circular(20)
                : const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(2),
                  ),
            reason: preset.label,
          );
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('selector identifies every completed interface with its logo', (
    tester,
  ) async {
    final controller = OrionController()
      ..setReducedMotion(true)
      ..setInterface(InterfacePreset.synapseBlue);
    addTearDown(controller.dispose);
    await _mount(tester, controller);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Open Synapse Blue'), findsOneWidget);
    expect(find.bySemanticsLabel('Use Synapse V3'), findsOneWidget);
    expect(find.bySemanticsLabel('Use Orion'), findsOneWidget);
    semantics.dispose();
    expect(find.text('UI Selection'), findsOneWidget);
    expect(find.text('Orion'), findsOneWidget);
    expect(find.text('Synapse V3'), findsOneWidget);
    expect(find.text('Synapse Blue'), findsOneWidget);
    expect(find.text('Synapse X'), findsOneWidget);
    expect(find.text('Synapse OG'), findsOneWidget);
    expect(_select(InterfacePreset.synapseV3), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.byType(InterfaceLogo), findsNWidgets(10));
    expect(
      tester
          .widget<FilledButton>(_select(InterfacePreset.synapseBlue))
          .onPressed,
      isNotNull,
    );
    expect(InterfacePresetDetails.available, hasLength(10));
    for (final preset in InterfacePresetDetails.available) {
      expect(
        find.text(preset.label),
        preset == InterfacePreset.awp ? findsNothing : findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('select-interface-${preset.name}')),
        findsOneWidget,
      );
    }
    expect(find.text('RC7'), findsNothing);
    expect(controller.selectedInterface, InterfacePreset.synapseBlue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'every selector raster logo is bundled and decodes with transparency',
    () async {
      for (final path in const [
        'assets/branding/orion-icon.png',
        'assets/interface_logos/synapse-s.png',
        'assets/interface_logos/synapse-s-2d.png',
        'assets/synapse_x/logo.png',
        'assets/original_krnl/pictureBox1.png',
        'assets/original_calamari/AppLogo.png',
        'assets/original_xeno/xeno-icon.png',
      ]) {
        final bytes = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        try {
          expect(frame.image.width, greaterThan(0), reason: path);
          expect(frame.image.height, greaterThan(0), reason: path);
          final rgba = await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(rgba, isNotNull, reason: path);
          final pixels = rgba!.buffer.asUint8List();
          var transparent = false;
          var visible = false;
          for (var alpha = 3; alpha < pixels.length; alpha += 4) {
            transparent |= pixels[alpha] < 255;
            visible |= pixels[alpha] > 0;
            if (transparent && visible) break;
          }
          expect(
            transparent,
            isTrue,
            reason: '$path should float over the theme',
          );
          expect(
            visible,
            isTrue,
            reason: '$path should contain visible artwork',
          );
        } finally {
          frame.image.dispose();
          codec.dispose();
        }
      }
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'selector preserves authored marks in ${brightness.name} theme',
      (tester) async {
        final controller = OrionController()..setReducedMotion(true);
        addTearDown(controller.dispose);
        await _mount(tester, controller, brightness: brightness);
        final zenith = _card(InterfacePreset.zenithV2);
        final v2 = find.descendant(of: zenith, matching: find.text('V2'));
        expect(v2, findsOneWidget);
        expect(tester.widget<Text>(v2).style!.fontFamily, 'OriginalNunito');
        expect(
          find.descendant(of: zenith, matching: find.byType(ShaderMask)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: zenith, matching: find.byType(Image)),
          findsNothing,
        );
        final awpText = tester.widget<Text>(
          find.descendant(
            of: _card(InterfacePreset.awp),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text && widget.textSpan?.toPlainText() == 'AWP.GG',
            ),
          ),
        );
        expect(awpText.style!.fontFamily, 'OriginalAwpUI');
        for (final preset in const [
          InterfacePreset.synapseV3,
          InterfacePreset.synapseBlue,
          InterfacePreset.synapse2017,
        ]) {
          final image = tester.widget<Image>(
            find.descendant(of: _card(preset), matching: find.byType(Image)),
          );
          expect(
            (image.image as AssetImage).assetName,
            preset == InterfacePreset.synapseV3
                ? 'assets/interface_logos/synapse-s.png'
                : 'assets/interface_logos/synapse-s-2d.png',
          );
          expect(
            image.color,
            isNull,
            reason: 'Preserve the multicolored Synapse S',
          );
        }
        for (final preset in const [
          InterfacePreset.orion,
          InterfacePreset.krnl,
          InterfacePreset.xeno,
        ]) {
          final image = tester.widget<Image>(
            find.descendant(of: _card(preset), matching: find.byType(Image)),
          );
          expect(
            image.color,
            brightness == Brightness.light ? isNotNull : isNull,
            reason: preset.label,
          );
        }
        expect(
          find.descendant(
            of: _card(InterfacePreset.synapseX),
            matching: find.byType(ColorFiltered),
          ),
          brightness == Brightness.light ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final width in [718.0, 636.0, 500.0]) {
    testWidgets('selector shows three compact cards per row at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = OrionController()..setReducedMotion(true);
      addTearDown(controller.dispose);
      await _mount(tester, controller, padding: EdgeInsets.zero);

      final presets = InterfacePresetDetails.available;
      final first = tester.getRect(_card(presets[0]));
      final second = tester.getRect(_card(presets[1]));
      final third = tester.getRect(_card(presets[2]));
      final nextRow = tester.getRect(_card(presets[3]));
      expect(second.top, closeTo(first.top, .01));
      expect(third.top, closeTo(first.top, .01));
      expect(second.left, greaterThan(first.right));
      expect(third.left, greaterThan(second.right));
      expect(nextRow.left, closeTo(first.left, .01));
      expect(nextRow.top, greaterThan(first.bottom));
      expect(first.height, lessThanOrEqualTo(145));
      expect(third.right, lessThanOrEqualTo(width + .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final viewport in const [(420.0, 2), (280.0, 1)]) {
    testWidgets(
      'selector falls back to ${viewport.$2} columns at width ${viewport.$1}',
      (tester) async {
        tester.view.physicalSize = Size(viewport.$1, 620);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = OrionController()..setReducedMotion(true);
        addTearDown(controller.dispose);
        await _mount(tester, controller, padding: EdgeInsets.zero);
        final presets = InterfacePresetDetails.available;
        final first = tester.getRect(_card(presets.first));
        final nextRow = tester.getRect(_card(presets[viewport.$2]));
        expect(nextRow.left, closeTo(first.left, .01));
        expect(nextRow.top, greaterThan(first.bottom));
        if (viewport.$2 == 2) {
          final second = tester.getRect(_card(presets[1]));
          expect(second.top, closeTo(first.top, .01));
          expect(second.left, greaterThan(first.right));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final compact in [false, true]) {
    for (final scale in [.8, 1.0, 1.25]) {
      testWidgets(
        'selector keeps logos and launch controls usable in ${compact ? 'compact' : 'normal'} mode at $scale GUI scale',
        (tester) async {
          final size = compact ? const Size(740, 470) : const Size(822, 523);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = OrionController()..setReducedMotion(true);
          addTearDown(controller.dispose);
          final requests = <InterfacePreset>[];
          await _mount(
            tester,
            controller,
            scale: scale,
            density: compact ? OrionDensity.compact : OrionDensity.comfortable,
            padding: compact
                ? const EdgeInsets.fromLTRB(76, 50, 8, 8)
                : const EdgeInsets.fromLTRB(94, 66, 22, 22),
            onSelectInterface: (preset) async => requests.add(preset),
          );
          final firstRow = InterfacePresetDetails.available
              .take(3)
              .map((preset) => tester.getRect(_card(preset)))
              .toList();
          expect(firstRow[1].top, closeTo(firstRow[0].top, .01));
          expect(firstRow[2].top, closeTo(firstRow[0].top, .01));
          for (final preset in InterfacePresetDetails.available) {
            final card = _card(preset);
            final logo = find.descendant(
              of: card,
              matching: find.byType(InterfaceLogo),
            );
            expect(logo, findsOneWidget, reason: preset.label);
            expect(tester.widget<InterfaceLogo>(logo).preset, preset);
            final cardRect = tester.getRect(card);
            final logoRect = tester.getRect(logo);
            expect(
              cardRect.contains(logoRect.center),
              isTrue,
              reason: preset.label,
            );
            expect(logoRect.width, greaterThan(0));
            expect(logoRect.height, greaterThan(0));

            final launch = _select(preset);
            await tester.ensureVisible(launch);
            await tester.pumpAndSettle();
            final rect = tester.getRect(launch);
            expect(rect.left, greaterThanOrEqualTo(0), reason: preset.label);
            expect(
              rect.right,
              lessThanOrEqualTo(size.width + .01),
              reason: preset.label,
            );
            expect(rect.top, greaterThanOrEqualTo(0), reason: preset.label);
            expect(
              rect.bottom,
              lessThanOrEqualTo(size.height + .01),
              reason: preset.label,
            );
            expect(launch.hitTestable(), findsOneWidget, reason: preset.label);
            await tester.tap(launch);
            await tester.pumpAndSettle();
            expect(requests.last, preset);
            expect(tester.takeException(), isNull, reason: preset.label);
          }
          expect(requests, InterfacePresetDetails.available);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'actual shell shows nine complete choices before scrolling in normal and compact mode',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final compact in [false, true]) {
        tester.view.physicalSize = compact
            ? const Size(740, 470)
            : const Size(822, 523);
        final controller = OrionController()
          ..setReducedMotion(true)
          ..setOrionCompactMode(compact)
          ..completeIntro();
        await controller.flushPersistence();
        await tester.pumpWidget(
          OrionApp(controller: controller, nativeWindow: false),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('UI Selection'));
        await tester.pumpAndSettle();

        final screen = find.byKey(const ValueKey('ui-selection'));
        final viewport = tester.getRect(
          find.descendant(
            of: screen,
            matching: find.byType(SingleChildScrollView),
          ),
        );
        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: screen, matching: find.byType(Scrollable)),
        );
        expect(scrollable.position.pixels, 0);
        for (final preset in InterfacePresetDetails.available.take(9)) {
          for (final item in [_card(preset), _select(preset)]) {
            final rect = tester.getRect(item);
            expect(
              rect.left,
              greaterThanOrEqualTo(viewport.left - .01),
              reason: '${preset.label} left / compact=$compact',
            );
            expect(
              rect.right,
              lessThanOrEqualTo(viewport.right + .01),
              reason: '${preset.label} right / compact=$compact',
            );
            expect(
              rect.top,
              greaterThanOrEqualTo(viewport.top - .01),
              reason: '${preset.label} top / compact=$compact',
            );
            expect(
              rect.bottom,
              lessThanOrEqualTo(viewport.bottom + .01),
              reason: '${preset.label} bottom / compact=$compact',
            );
          }
          expect(
            _select(preset).hitTestable(),
            findsOneWidget,
            reason: '${preset.label} / compact=$compact',
          );
        }
        expect(scrollable.position.pixels, 0);
        final last = InterfacePresetDetails.available.last;
        expect(
          tester.getRect(_card(last)).bottom,
          greaterThan(viewport.bottom),
        );
        expect(_select(last).hitTestable(), findsNothing);
        expect(scrollable.position.maxScrollExtent, greaterThan(0));
        await tester.ensureVisible(_select(last));
        await tester.pumpAndSettle();
        expect(_select(last).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await controller.flushPersistence();
      }
    },
  );

  testWidgets(
    'Open editor invokes the supplied shortcut without changing preferences',
    (tester) async {
      final controller = OrionController()..setReducedMotion(true);
      addTearDown(controller.dispose);
      var openCount = 0;
      await _mount(tester, controller, onOpenWorkspace: () => openCount++);
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      expect(openCount, 1);
      expect(controller.selectedInterface, InterfacePreset.orion);
      expect(_select(InterfacePreset.synapseV3), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'every available selection and dirty scripts survive a restart',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'orion-interface-test-',
      );
      final controller = OrionController(storageDirectory: directory);
      OrionController? restored;
      try {
        await controller.initialize();
        controller.updateDocumentContent(
          controller.activeDocumentId,
          'print("persisted")',
        );
        for (final preset in InterfacePresetDetails.available) {
          controller.setInterface(preset);
          await controller.flushPersistence();
          restored = OrionController(storageDirectory: directory);
          await restored.initialize();
          expect(restored.selectedInterface, preset, reason: preset.label);
          expect(restored.activeDocument.content, 'print("persisted")');
          expect(restored.activeDocument.isDirty, isTrue);
          restored.dispose();
          await restored.flushPersistence();
          restored = null;
        }
      } finally {
        controller.dispose();
        await controller.flushPersistence();
        restored?.dispose();
        if (restored != null) await restored.flushPersistence();
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets('pending interface switch prevents duplicate requests', (
    tester,
  ) async {
    final c = OrionController()..setReducedMotion(true);
    addTearDown(c.dispose);
    final completion = Completer<void>();
    final selected = <InterfacePreset>[];
    await _mount(
      tester,
      c,
      onSelectInterface: (preset) {
        selected.add(preset);
        return completion.future;
      },
    );
    await tester.tap(_select(InterfacePreset.synapseV3));
    await tester.pump();
    await tester.tap(find.text('Open editor'));
    await tester.pump();
    expect(selected, [InterfacePreset.synapseV3]);
    for (final preset in InterfacePresetDetails.available) {
      expect(
        tester.widget<FilledButton>(_select(preset)).onPressed,
        isNull,
        reason: '${preset.label} must wait for the active switch',
      );
    }
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completion.complete();
    await tester.pumpAndSettle();
    for (final preset in InterfacePresetDetails.available) {
      expect(tester.widget<FilledButton>(_select(preset)).onPressed, isNotNull);
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 and back keeps dirty tabs and the active script', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(961, 523);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = OrionController()
      ..setReducedMotion(true)
      ..completeIntro();
    addTearDown(c.dispose);
    await tester.pumpWidget(OrionApp(controller: c, nativeWindow: false));
    await tester.pumpAndSettle();
    const first = 'print("kept in both interfaces")';
    await tester.enterText(find.byKey(const ValueKey('code-editor')), first);
    c.newDocument();
    await tester.pumpAndSettle();
    const second = 'local unsaved = 42';
    await tester.enterText(find.byKey(const ValueKey('code-editor')), second);
    final active = c.activeDocumentId;
    await tester.tap(find.byTooltip('UI Selection'));
    await tester.pumpAndSettle();
    await tester.tap(_select(InterfacePreset.synapseV3));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(c.selectedInterface, InterfacePreset.synapseV3);
    expect(find.text('Back to Orion'), findsNothing);
    expect(find.byTooltip('UI Selection'), findsNothing);
    expect(c.documents.map((doc) => doc.content), [first, second]);
    expect(c.activeDocumentId, active);
    const changed = 'local unsaved = 43';
    await tester.enterText(find.byKey(const ValueKey('code-editor')), changed);
    await tester.pumpAndSettle();
    await _returnToOrion(tester, InterfacePreset.synapseV3);
    await tester.pumpAndSettle();
    expect(c.selectedInterface, InterfacePreset.orion);
    expect(c.activeDocumentId, active);
    expect(c.documents.map((doc) => doc.content), [first, changed]);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('code-editor')))
          .controller!
          .text,
      changed,
    );
    expect(find.text('Bridge offline'), findsOneWidget);
    expect(find.text('Orion Bridge'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await c.flushPersistence();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'all source ports share dirty scripts through selection and back',
    (tester) async {
      tester.view.physicalSize = const Size(1050, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = OrionController()
        ..setReducedMotion(true)
        ..completeIntro();
      addTearDown(c.dispose);
      c.updateDocumentContent(c.activeDocumentId, 'print("first draft")');
      c.newDocument();
      final active = c.activeDocumentId;
      var draft = 'print("shared draft")';
      c.updateDocumentContent(active, draft);
      await tester.pumpWidget(OrionApp(controller: c, nativeWindow: false));
      await tester.pumpAndSettle();
      for (final preset in InterfacePresetDetails.available.where(
        (preset) => preset.isStandalone,
      )) {
        await tester.tap(find.byTooltip('UI Selection'));
        await tester.pumpAndSettle();
        final choose = find.byKey(ValueKey('select-interface-${preset.name}'));
        await tester.ensureVisible(choose);
        await tester.tap(choose);
        await _enterSourceEditor(tester, preset);
        expect(c.selectedInterface, preset);
        expect(c.activeDocumentId, active);
        expect(c.activeDocument.content, draft);
        draft = 'print("edited in ${preset.name}")';
        await tester.enterText(
          find.byKey(const ValueKey('code-editor')),
          draft,
        );
        await _pumpFrames(tester);
        await _returnToOrion(tester, preset);
        expect(c.selectedInterface, InterfacePreset.orion);
        expect(c.activeDocumentId, active);
        expect(c.documents.map((document) => document.content), [
          'print("first draft")',
          draft,
        ]);
        expect(tester.takeException(), isNull, reason: preset.label);
      }
      await c.flushPersistence();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Blue loader replay preference replays other source shells', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(961, 523);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = OrionController()..completeIntro();
    addTearDown(c.dispose);
    await tester.pumpWidget(OrionApp(controller: c, nativeWindow: false));
    await tester.pumpAndSettle();
    for (var visit = 0; visit < 3; visit++) {
      final replay = visit == 2;
      c.setInterfacePreference(
        InterfacePreset.synapseBlue,
        'playLoadingScreenOnShellChange',
        replay,
      );
      await tester.tap(find.byTooltip('UI Selection'));
      await tester.pumpAndSettle();
      await tester.tap(_select(InterfacePreset.synapseX));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      if (replay) {
        expect(find.text('Initializing...'), findsOneWidget);
      } else if (visit == 1) {
        expect(find.text('Initializing...'), findsNothing);
      }
      // First entry always loads. Subsequent default entries go straight back.
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('code-editor')).evaluate().isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(find.text('Initializing...'), findsNothing);
      await _returnToOrion(tester, InterfacePreset.synapseX);
    }
    await c.flushPersistence();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [
    const Size(720, 480),
    const Size(822, 523),
    const Size(1440, 940),
  ]) {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      testWidgets(
        'selector fits ${size.width.toInt()}x${size.height.toInt()} ${brightness.name}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = OrionController()
            ..setReducedMotion(size.width < 1000);
          addTearDown(controller.dispose);
          var opened = false;
          await _mount(
            tester,
            controller,
            brightness: brightness,
            onOpenWorkspace: () => opened = true,
          );
          expect(find.text('Orion'), findsOneWidget);
          expect(find.text('Synapse V3'), findsOneWidget);
          expect(_select(InterfacePreset.synapseV3), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
          expect(tester.binding.hasScheduledFrame, isFalse);
          await tester.ensureVisible(find.text('Open editor'));
          await tester.tap(find.text('Open editor'));
          expect(opened, isTrue);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'every source editor exposes the shared live multi-client controls',
    (tester) async {
      tester.view.physicalSize = const Size(1050, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final preset in InterfacePresetDetails.available.where(
        (preset) => preset.isStandalone,
      )) {
        final c = _SourceClientController()
          ..setReducedMotion(true)
          ..completeIntro()
          ..setInterface(preset);
        c.updateDocumentContent(
          c.activeDocumentId,
          'print("clients stay shared")',
        );
        final active = c.activeDocumentId;
        c.applyWindowState({
          ...c.exportWindowState(),
          'bridgeListening': true,
          'bridgeClients': [
            {
              'identifier': 'User1',
              'username': 'Alex',
              'transport': 'port',
              'sessionId': 'alex',
            },
            {
              'identifier': 'User2',
              'username': 'Sam',
              'transport': 'websocket',
              'sessionId': 'sam',
            },
          ],
        });
        await tester.pumpWidget(OrionApp(controller: c, nativeWindow: false));
        await _enterSourceEditor(tester, preset);
        final execute = switch (preset) {
          InterfacePreset.synapseV3 => find.byTooltip(
            'Execute script · Ctrl Enter',
          ),
          InterfacePreset.synapseBlue => find.text('Execute'),
          InterfacePreset.synapseX => find.byKey(const ValueKey('x-action-0')),
          InterfacePreset.synapse2017 => find.byKey(
            const ValueKey('og-action/Execute'),
          ),
          InterfacePreset.zenithV2 => find.text('Execute'),
          InterfacePreset.awp => find.byTooltip('Execute').first,
          InterfacePreset.xeno => find.byKey(const ValueKey('xeno-execute')),
          InterfacePreset.krnl => find.byKey(const ValueKey('krnl-action-0')),
          InterfacePreset.calamari => find.byKey(
            const ValueKey('calamari-execute'),
          ),
          _ => throw StateError(preset.label),
        };
        expect(execute.hitTestable(), findsOneWidget, reason: preset.label);
        await tester.tap(execute);
        await _pumpFrames(tester, 3);
        expect(
          c.executedSource,
          'print("clients stay shared")',
          reason: '${preset.label} Execute',
        );
        switch (preset) {
          case InterfacePreset.synapseV3:
            await tester.tap(find.byKey(const ValueKey('v3-clients')));
          case InterfacePreset.synapseBlue:
            await tester.tap(find.byKey(const ValueKey('blue-clients')));
          case InterfacePreset.synapseX:
            await tester.tap(find.byKey(const ValueKey('x-clients')));
          case InterfacePreset.synapse2017:
            await tester.tap(
              find.byKey(const ValueKey('og-action/Settings & Clients')),
            );
            await _pumpFrames(tester);
            await tester.tap(find.byKey(const ValueKey('og-clients')));
          case InterfacePreset.zenithV2:
            await tester.tap(find.byKey(const ValueKey('zenith-clients')));
          case InterfacePreset.awp:
            await tester.tap(find.byKey(const ValueKey('awp-clients')));
            await _pumpFrames(tester, 3);
            expect(
              find.byKey(const ValueKey('awp-client-User1')),
              findsOneWidget,
            );
            await tester.tap(find.byKey(const ValueKey('awp-manage-clients')));
          case InterfacePreset.xeno:
            await tester.tap(find.byKey(const ValueKey('xeno-clients')));
            await _pumpFrames(tester, 3);
            expect(find.text('Alex'), findsOneWidget);
            expect(find.text('Sam'), findsOneWidget);
            await tester.tap(find.text('Bridge setup & management'));
          case InterfacePreset.krnl:
            await tester.tap(find.byKey(const ValueKey('krnl-clients')));
          case InterfacePreset.calamari:
            await tester.tap(find.byKey(const ValueKey('calamari-clients')));
          default:
            fail('Unexpected source ${preset.name}');
        }
        await _pumpFrames(tester);
        expect(
          find.byType(BridgeClientManagerPanel),
          findsOneWidget,
          reason: preset.label,
        );
        expect(
          find.descendant(
            of: find.byType(BridgeClientManagerPanel),
            matching: find.text('Alex'),
          ),
          findsOneWidget,
          reason: preset.label,
        );
        expect(
          find.descendant(
            of: find.byType(BridgeClientManagerPanel),
            matching: find.text('Sam'),
          ),
          findsOneWidget,
          reason: preset.label,
        );
        await tester.tap(
          find
              .descendant(
                of: find.byType(BridgeClientManagerPanel),
                matching: find.byType(Checkbox),
              )
              .first,
        );
        await _pumpFrames(tester, 3);
        expect(c.bridgeTargetAll, false, reason: preset.label);
        expect(c.selectedBridgeClients, {'User2'}, reason: preset.label);
        expect(c.activeDocumentId, active, reason: preset.label);
        expect(
          c.activeDocument.content,
          'print("clients stay shared")',
          reason: preset.label,
        );
        expect(tester.takeException(), isNull, reason: preset.label);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    },
  );
}

Finder _select(InterfacePreset preset) =>
    find.byKey(ValueKey('select-interface-${preset.name}'));

Finder _card(InterfacePreset preset) =>
    find.byKey(ValueKey('interface-card-${preset.name}'));

Future<void> _mount(
  WidgetTester tester,
  OrionController controller, {
  Brightness brightness = Brightness.dark,
  VoidCallback? onOpenWorkspace,
  Future<void> Function(InterfacePreset)? onSelectInterface,
  EdgeInsets padding = const EdgeInsets.fromLTRB(94, 66, 22, 22),
  OrionDensity density = OrionDensity.comfortable,
  double scale = 1,
}) async {
  // Preference setup can schedule a save even without an initialized store.
  await controller.flushPersistence();
  await tester.pumpWidget(
    MaterialApp(
      theme: orionTheme(brightness, controller.accentColor).copyWith(
        extensions: [
          ...orionTheme(brightness, controller.accentColor).extensions.values,
          density,
        ],
      ),
      builder: (context, child) => UiScaleViewport(scale: scale, child: child!),
      home: Scaffold(
        body: Padding(
          padding: padding,
          child: UISelectionScreen(
            controller: controller,
            onOpenWorkspace: onOpenWorkspace,
            onSelectInterface: onSelectInterface,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Bounded pumping also works while KRNL's source accent animation is active.
Future<void> _pumpFrames(WidgetTester tester, [int frames = 8]) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _enterSourceEditor(
  WidgetTester tester,
  InterfacePreset preset,
) async {
  if (preset == InterfacePreset.synapseV3) await _pumpFrames(tester, 21);
  for (var frame = 0; frame < 110; frame++) {
    final login = find
        .byKey(
          ValueKey(switch (preset) {
            InterfacePreset.awp => 'awp-login',
            InterfacePreset.zenithV2 => 'zenith-login',
            InterfacePreset.calamari => 'calamari-login',
            _ => 'no-local-login',
          }),
        )
        .hitTestable();
    if (login.evaluate().isNotEmpty) {
      if (preset == InterfacePreset.awp) {
        await tester.enterText(
          find.byKey(const ValueKey('awp-login-username')),
          'local-test',
        );
        await tester.enterText(
          find.byKey(const ValueKey('awp-login-password')),
          'local-only',
        );
      } else if (preset == InterfacePreset.calamari) {
        await tester.enterText(
          find.byKey(const ValueKey('calamari-username')),
          'local-test',
        );
        await tester.enterText(
          find.byKey(const ValueKey('calamari-password')),
          'local-only',
        );
      } else {
        final inputs = find.byType(TextField);
        await tester.enterText(inputs.first, 'local-test');
        await tester.enterText(inputs.last, 'local-only');
      }
      await tester.tap(login);
      await _pumpFrames(tester);
      if (preset == InterfacePreset.zenithV2) {
        await tester.tap(find.byKey(const ValueKey('zenith-nav-1')));
        await _pumpFrames(tester);
      }
    }
    if (find
        .byKey(const ValueKey('code-editor'))
        .hitTestable()
        .evaluate()
        .isNotEmpty) {
      await _pumpFrames(tester, 3);
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail(
    '${preset.label} did not expose its editor after its local login/intro.',
  );
}

Future<void> _returnToOrion(WidgetTester tester, InterfacePreset preset) async {
  switch (preset) {
    case InterfacePreset.synapseV3:
      await tester.tap(find.byTooltip('Settings'));
    case InterfacePreset.synapseBlue:
      await tester.tap(find.byKey(const ValueKey('blue-nav-3')));
    case InterfacePreset.synapseX:
      await tester.tap(find.text('Options'));
    case InterfacePreset.synapse2017:
      await tester.tap(
        find.byKey(const ValueKey('og-action/Settings & Clients')),
      );
    case InterfacePreset.zenithV2:
      await tester.tap(find.byKey(const ValueKey('zenith-nav-5')));
    case InterfacePreset.awp:
      await tester.tap(find.text('Scripting'));
      await _pumpFrames(tester, 3);
      await tester.tap(find.byKey(const ValueKey('awp-menu-settings')));
    case InterfacePreset.xeno:
      await tester.tap(find.byKey(const ValueKey('xeno-settings')));
    case InterfacePreset.krnl:
      await tester.tap(find.byKey(const ValueKey('krnl-options')));
    case InterfacePreset.calamari:
      await tester.tap(find.byKey(const ValueKey('calamari-tools-tab')));
    case InterfacePreset.orion:
    case InterfacePreset.rc7:
      fail('No source Settings return route for ${preset.label}.');
  }
  await _pumpFrames(tester);
  final key = switch (preset) {
    InterfacePreset.synapseV3 => 'v3-back-to-orion',
    InterfacePreset.synapseBlue => 'blue-back-to-orion',
    InterfacePreset.synapseX => 'x-back-to-orion',
    InterfacePreset.synapse2017 => 'og-back-to-orion',
    InterfacePreset.zenithV2 => 'zenith-back-to-orion',
    InterfacePreset.awp => 'awp-back-to-orion',
    InterfacePreset.xeno => 'xeno-back-to-orion',
    InterfacePreset.krnl => 'krnl-back-to-orion',
    InterfacePreset.calamari => 'calamari-back-to-orion',
    _ => '',
  };
  final back = find.byKey(ValueKey(key));
  expect(back, findsOneWidget);
  await tester.ensureVisible(back);
  await _pumpFrames(tester, 3);
  await tester.tap(back);
  await _pumpFrames(tester);
}
