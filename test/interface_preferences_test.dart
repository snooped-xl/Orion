import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/interface_window_profile.dart';
import 'package:orion/state/orion_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'shell preferences remain independent and survive recovery with drafts',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'orion-shell-state-',
      );
      final original = OrionController(storageDirectory: directory);
      OrionController? restored;
      try {
        await original.initialize();
        original.setInterfacePreference(InterfacePreset.synapseBlue, 'theme', {
          'accent': 0xff2472ff,
          'stops': [0xff111111, 0xff222222],
        });
        original.setInterfacePreference(InterfacePreset.synapseX, 'theme', {
          'accent': 0xffff7e00,
        });
        original.setInterfacePreference(
          InterfacePreset.synapse2017,
          'edgeCurve',
          true,
        );
        original.setInterface(InterfacePreset.synapseX);
        original.updateDocumentContent(
          original.activeDocumentId,
          'print("unsaved")',
        );
        await original.flushPersistence();
        restored = OrionController(storageDirectory: directory);
        await restored.initialize();
        expect(restored.selectedInterface, InterfacePreset.synapseX);
        expect(restored.activeDocument.content, 'print("unsaved")');
        expect(
          restored.getInterfacePreferences(
            InterfacePreset.synapseBlue,
          )['theme'],
          {
            'accent': 0xff2472ff,
            'stops': [0xff111111, 0xff222222],
          },
        );
        expect(
          restored.getInterfacePreferences(InterfacePreset.synapseX)['theme'],
          {'accent': 0xffff7e00},
        );
        expect(
          restored.getInterfacePreferences(
            InterfacePreset.synapse2017,
          )['edgeCurve'],
          true,
        );
        restored.resetInterfacePreferences(InterfacePreset.synapseX);
        expect(
          restored.getInterfacePreferences(InterfacePreset.synapseX),
          isEmpty,
        );
        expect(
          restored.getInterfacePreferences(InterfacePreset.synapseBlue),
          isNotEmpty,
        );
      } finally {
        original.dispose();
        await original.flushPersistence();
        restored?.dispose();
        await restored?.flushPersistence();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'mutable input cannot alter saved preferences without notification',
    () async {
      final c = OrionController();
      final colors = <String, Object?>{
        'stops': [1, 2],
      };
      c.setInterfacePreference(InterfacePreset.synapseBlue, 'theme', colors);
      (colors['stops'] as List).add(3);
      final saved = c.getInterfacePreferences(InterfacePreset.synapseBlue);
      expect(saved['theme'], {
        'stops': [1, 2],
      });
      expect(() => saved['theme'] = 'changed', throwsUnsupportedError);
      expect(
        () => ((saved['theme'] as Map)['stops'] as List).add(4),
        throwsUnsupportedError,
      );
      c.setInterfacePreference(
        InterfacePreset.synapseBlue,
        'number',
        double.nan,
      );
      expect(
        () =>
            jsonEncode(c.getInterfacePreferences(InterfacePreset.synapseBlue)),
        returnsNormally,
      );
      c.dispose();
      await c.flushPersistence();
    },
  );

  test(
    'source window profiles distinguish cold loaders and full shells',
    () async {
      final c = OrionController();
      for (final (preset, main, loader) in const [
        (InterfacePreset.synapseBlue, Size(714, 393), Size(290, 355)),
        (InterfacePreset.synapseX, Size(801, 355), Size(418, 117)),
        (InterfacePreset.synapse2017, Size(838, 372), Size(265, 171)),
      ]) {
        expect(InterfaceWindowProfile.forInterface(c, preset).size, main);
        expect(InterfaceWindowProfile.forInterface(c, preset).resizable, false);
        expect(
          InterfaceWindowProfile.forInterface(c, preset, coldStart: true).size,
          loader,
        );
        c.setInterfacePreference(preset, 'resizableWindow', true);
        expect(InterfaceWindowProfile.forInterface(c, preset).resizable, true);
        expect(
          InterfaceWindowProfile.forInterface(
            c,
            preset,
            coldStart: true,
          ).resizable,
          false,
        );
      }
      expect(
        InterfaceWindowProfile.forInterface(c, InterfacePreset.orion).size,
        const Size(822, 523),
      );
      for (final (preset, size, minimum) in const [
        (InterfacePreset.zenithV2, Size(1050, 650), Size(760, 500)),
        (InterfacePreset.awp, Size(820, 560), Size(620, 420)),
        (InterfacePreset.xeno, Size(700, 400), Size(560, 320)),
        (InterfacePreset.krnl, Size(679, 345), Size(679, 345)),
        (InterfacePreset.calamari, Size(521, 365), Size(521, 365)),
      ]) {
        final cold = InterfaceWindowProfile.forInterface(
          c,
          preset,
          coldStart: true,
        );
        expect(cold.size, size);
        expect(cold.minimumSize, minimum);
        expect(cold.resizable, false);
        c.setInterfacePreference(preset, 'resizable', true);
        c.setInterfacePreference(preset, 'alwaysOnTop', true);
        final warm = InterfaceWindowProfile.forInterface(c, preset);
        expect(warm.size, size);
        expect(warm.minimumSize, minimum);
        expect(warm.resizable, true);
        expect(warm.alwaysOnTop, true);
      }
      c.dispose();
      await c.flushPersistence();
    },
  );
}
