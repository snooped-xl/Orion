import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/screens/synapse_theme_studio.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/orion_glass.dart';
import 'package:orion/widgets/synapse_studio_preview.dart';

void main() {
  testWidgets(
    'Studio Glass chrome clears its panels without changing the draft',
    (tester) async {
      tester.view.physicalSize = const Size(1180, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = OrionController(persistChanges: false)..setReducedMotion(true);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        AnimatedBuilder(
          animation: c,
          builder: (_, _) => MaterialApp(
            themeAnimationDuration: Duration.zero,
            theme: orionTheme(
              Brightness.dark,
              c.orionTheme.accent,
              preferences: c.orionTheme,
              reducedMotion: true,
            ),
            home: SynapseThemeStudioScreen(
              controller: c,
              preset: InterfacePreset.synapseV3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final workbench = find.byKey(const ValueKey('studio-workbench'));
      expect(tester.widget<Material>(workbench).color!.a, 1);
      final name = find.descendant(
        of: find.byKey(
          ValueKey('studio-theme-name:${InterfacePreset.synapseV3}'),
        ),
        matching: find.byType(TextField),
      );
      await tester.enterText(name, 'Unapplied draft');
      await tester.pumpAndSettle();
      final before = tester
          .widget<SynapseStudioPreview>(find.byType(SynapseStudioPreview))
          .theme;
      final glass = OrionThemePreferences.builtInPresets
          .singleWhere((preset) => preset.id == 'liquid-glass')
          .preferences;
      c.setOrionTheme(glass);
      await tester.pumpAndSettle();
      expect(tester.widget<Material>(workbench).color, Colors.transparent);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        Colors.transparent,
      );
      expect(
        find.ancestor(of: workbench, matching: find.byType(OrionGlassSurface)),
        findsOneWidget,
      );
      expect(
        Theme.of(tester.element(name)).inputDecorationTheme.fillColor!.a,
        lessThan(.1),
      );
      expect(
        tester
            .widget<SynapseStudioPreview>(find.byType(SynapseStudioPreview))
            .theme
            .toJson(),
        before.toJson(),
      );
      expect(
        tester.widget<TextField>(name).controller!.text,
        'Unapplied draft',
      );
      expect(
        c.getInterfacePreferences(InterfacePreset.synapseV3)['themeStudio'],
        isNull,
      );
      c.resetOrionTheme();
      await tester.pumpAndSettle();
      expect(tester.widget<Material>(workbench).color!.a, 1);
      expect(
        tester.widget<TextField>(name).controller!.text,
        'Unapplied draft',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
