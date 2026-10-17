import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/companion_window.dart';
import 'package:orion/models/companion_window_profile.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/interface_window_profile.dart';
import 'package:orion/models/synapse_studio_theme.dart';
import 'package:orion/services/synapse_theme_catalog.dart';
import 'package:orion/state/orion_controller.dart';

void main() {
  test('only Theme Studio companions opt into the expressive window curve', () {
    for (final kind in CompanionWindowKind.values) {
      expect(
        CompanionWindowProfile.forKind(kind).cornerRadius,
        kind.isThemeStudio ? 20 : 0,
        reason: kind.name,
      );
    }
  });
  for (final preset in SynapseThemeCatalog.synapsePresets) {
    test(
      '${preset.name} uses applied main size after loading and resets to source size',
      () {
        final controller = OrionController(persistChanges: false);
        addTearDown(controller.dispose);
        final source = InterfaceWindowProfile.forInterface(controller, preset);
        final loader = InterfaceWindowProfile.forInterface(
          controller,
          preset,
          coldStart: true,
        );
        final theme = SynapseThemeCatalog.defaults(
          preset,
        ).withWindow('main', SynapseStudioWindow(width: 1100, height: 720));
        controller.setInterfacePreference(
          preset,
          'themeStudio',
          theme.toJson(),
        );
        expect(
          InterfaceWindowProfile.forInterface(controller, preset).size,
          const Size(1100, 720),
        );
        if (preset != InterfacePreset.synapseV3) {
          expect(
            InterfaceWindowProfile.forInterface(
              controller,
              preset,
              coldStart: true,
            ).size,
            loader.size,
          );
        }
        controller.setInterfacePreference(
          preset,
          'themeStudio',
          SynapseThemeCatalog.defaults(preset).toJson(),
        );
        expect(
          InterfaceWindowProfile.forInterface(controller, preset).size,
          source.size,
        );
        expect(
          InterfaceWindowProfile.forInterface(
            controller,
            InterfacePreset.orion,
          ).size,
          InterfaceWindowProfile.orionSize,
        );
        final studio = CompanionWindowProfile.forKind(
          CompanionThemeStudioKind.forPreset(preset),
        );
        expect(studio.size, const Size(1180, 760));
        expect(studio.minimumSize, const Size(800, 560));
        expect(studio.resizable, true);
        expect(studio.modal, false);
      },
    );
  }
  test('Orion Studio dimensions compose with compact mode and reset', () {
    final c = OrionController(persistChanges: false);
    addTearDown(c.dispose);
    c.applyThemeStudioState(
      InterfacePreset.orion,
      document: SynapseThemeCatalog.defaults(InterfacePreset.orion)
          .withWindow('main', SynapseStudioWindow(width: 1000, height: 700))
          .toJson(),
    );
    expect(
      InterfaceWindowProfile.forInterface(c, InterfacePreset.orion).size,
      const Size(1000, 700),
    );
    c.setOrionCompactMode(true);
    expect(
      InterfaceWindowProfile.forInterface(c, InterfacePreset.orion).size,
      InterfaceWindowProfile.compactOrionSizeFor(const Size(1000, 700)),
    );
    c.setInterfacePreference(InterfacePreset.orion, 'themeStudio', null);
    expect(
      InterfaceWindowProfile.forInterface(c, InterfacePreset.orion).size,
      InterfaceWindowProfile.orionCompactSize,
    );
    final studio = CompanionWindowProfile.forKind(
      CompanionWindowKind.orionThemeStudio,
    );
    expect(studio.title, 'Theme Studio');
    expect(studio.resizable, true);
    expect(studio.modal, false);
  });
}
