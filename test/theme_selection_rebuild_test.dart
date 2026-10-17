import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/synapse_studio_theme.dart';
import 'package:orion/screens/theme_control_screen.dart';
import 'package:orion/services/synapse_theme_catalog.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/selected_builder.dart';
import 'package:orion/widgets/synapse_theme_surface.dart';

void main() {
  testWidgets(
    'Theme Control ignores editor updates but reflects every control',
    (tester) async {
      final c = OrionController(persistChanges: false);
      tester.view.physicalSize = const Size(700, 450);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: orionTheme(Brightness.dark, c.orionTheme.accent),
          home: Scaffold(body: ThemeControlScreen(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      final targets = tester
          .elementList(find.byWidgetPredicate((w) => w is SelectedBuilder))
          .toSet();
      var rebuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (targets.contains(element)) rebuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      for (var i = 0; i < 100; i++) {
        c.updateDocumentContent(c.activeDocumentId, 'print($i)');
        await tester.pump();
      }
      expect(rebuilds, 0);
      Future<void> updates(VoidCallback update) async {
        final before = rebuilds;
        update();
        await tester.pumpAndSettle();
        expect(rebuilds, greaterThan(before));
      }

      await updates(
        () => c.setOrionTheme(c.orionTheme.copyWith(surfaceTint: .6)),
      );
      final saved = c.saveOrionTheme('Rebuild check');
      await tester.pumpAndSettle();
      final afterSave = rebuilds;
      expect(afterSave, greaterThan(1));
      await updates(() => c.deleteSavedOrionTheme(saved.id));
      final logo = await rootBundle.load('assets/branding/orion-logo.png');
      await updates(() => c.setCustomLogo(logo.buffer.asUint8List()));
      await updates(() => c.setUiScale(1.1));
      final beforeWindowMode = rebuilds;
      c.setOrionCompactMode(true);
      await tester.pumpAndSettle();
      expect(
        rebuilds,
        beforeWindowMode,
        reason: 'Window size modes now belong to Settings',
      );
      await updates(() => c.setReducedMotion(true));
      final beforeEdit = rebuilds;
      c.updateDocumentContent(c.activeDocumentId, 'print("still unrelated")');
      await tester.pump();
      expect(rebuilds, beforeEdit);
      debugOnRebuildDirtyWidget = previous;
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  for (final preset in [
    InterfacePreset.synapseV3,
    InterfacePreset.synapseBlue,
    InterfacePreset.synapseX,
    InterfacePreset.synapse2017,
  ]) {
    testWidgets('${preset.name} decorators filter edits and apply Studio', (
      tester,
    ) async {
      final c = OrionController(persistChanges: false);
      await tester.pumpWidget(
        MaterialApp(
          home: SynapseThemeSurface(
            controller: c,
            preset: preset,
            windowId: 'main',
            child: SynapseThemeElement(
              controller: c,
              preset: preset,
              windowId: 'main',
              elementId: 'logo',
              child: SynapseThemeLogo(
                controller: c,
                preset: preset,
                windowId: 'main',
                child: const SizedBox(width: 20, height: 20),
              ),
            ),
          ),
        ),
      );
      final targets = tester
          .elementList(find.byWidgetPredicate((w) => w is SelectedBuilder))
          .toSet();
      expect(targets.length, 3);
      var rebuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (targets.contains(element)) rebuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      for (var i = 0; i < 100; i++) {
        c.updateDocumentContent(c.activeDocumentId, 'print($i)');
        await tester.pump();
      }
      expect(rebuilds, 0);
      final themed = SynapseThemeCatalog.current(c, preset)
          .copyWith(fontFamily: 'SynapseInter')
          .withElement(
            'main',
            'logo',
            SynapseStudioElement(fill: 0xffaabbcc, x: 4, opacity: .5),
          );
      c.applyThemeStudioState(preset, document: themed.toJson());
      await tester.pumpAndSettle();
      expect(rebuilds, greaterThan(0));
      expect(find.byType(Transform), findsOneWidget);
      final scope = tester.widgetList<SynapseThemeElementStyleScope>(
        find.byType(SynapseThemeElementStyleScope),
      );
      expect(scope.any((w) => w.style?.fill == 0xffaabbcc), isTrue);
      expect(scope.every((w) => w.fontFamily == 'SynapseInter'), isTrue);
      debugOnRebuildDirtyWidget = previous;
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
