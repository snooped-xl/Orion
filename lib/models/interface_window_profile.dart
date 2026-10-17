import 'package:flutter/services.dart';

import '../state/orion_controller.dart';
import 'interface_preset.dart';
import '../services/synapse_theme_catalog.dart';

/// Original shell dimensions. Each port owns its loader-to-main transition and
/// source-sized auxiliary panels after the initial window has been configured.
class InterfaceWindowProfile {
  const InterfaceWindowProfile({
    required this.size,
    required this.minimumSize,
    required this.resizable,
    required this.alwaysOnTop,
  });

  final Size size, minimumSize;
  final bool resizable, alwaysOnTop;

  static const orionSize = Size(822, 523);
  static const orionEnlargedSize = Size(1045, 648);
  static const orionMinimumSize = Size(720, 480);
  static const orionCompactSize = Size(740, 470);
  static const orionCompactMinimumSize = Size(680, 420);

  /// Compact custom-sized windows by the same proportion as the default shell.
  static Size compactOrionSizeFor(Size normal) => Size(
    (normal.width * orionCompactSize.width / orionSize.width)
        .roundToDouble()
        .clamp(orionCompactMinimumSize.width, 16384),
    (normal.height * orionCompactSize.height / orionSize.height)
        .roundToDouble()
        .clamp(orionCompactMinimumSize.height, 16384),
  );

  static InterfaceWindowProfile forInterface(
    OrionController controller,
    InterfacePreset preset, {
    bool coldStart = false,
  }) {
    if (preset == InterfacePreset.orion) {
      final size = SynapseThemeCatalog.windowSize(
        SynapseThemeCatalog.current(controller, preset),
        preset,
        'main',
        compactMode: controller.orionCompactMode,
        enlargedMode: controller.orionEnlargedMode,
      );
      return InterfaceWindowProfile(
        size: size,
        minimumSize: controller.orionCompactMode
            ? orionCompactMinimumSize
            : orionMinimumSize,
        resizable: true,
        alwaysOnTop: controller.alwaysOnTop,
      );
    }
    if (preset == InterfacePreset.synapseV3) {
      return _studioProfile(
        controller,
        preset,
        InterfaceWindowProfile(
          size: const Size(961, 461),
          minimumSize: const Size(720, 400),
          resizable: controller.synapsePreferences.resizable,
          alwaysOnTop: controller.synapsePreferences.alwaysOnTop,
        ),
      );
    }
    final original = switch (preset) {
      InterfacePreset.zenithV2 => (const Size(1050, 650), const Size(760, 500)),
      InterfacePreset.awp => (const Size(820, 560), const Size(620, 420)),
      InterfacePreset.xeno => (const Size(700, 400), const Size(560, 320)),
      InterfacePreset.krnl => (const Size(679, 345), const Size(679, 345)),
      InterfacePreset.calamari => (const Size(521, 365), const Size(521, 365)),
      _ => null,
    };
    if (original != null) {
      final preferences = controller.getInterfacePreferences(preset);
      return InterfaceWindowProfile(
        size: original.$1,
        minimumSize: original.$2,
        resizable: preferences['resizable'] == true,
        alwaysOnTop: preferences['alwaysOnTop'] == true,
      );
    }
    final sizes = switch (preset) {
      InterfacePreset.synapseBlue => (
        const Size(714, 393),
        const Size(290, 355),
      ),
      InterfacePreset.synapseX => (const Size(801, 355), const Size(418, 117)),
      InterfacePreset.synapse2017 => (
        const Size(838, 372),
        const Size(265, 171),
      ),
      _ => (const Size(822, 523), const Size(822, 523)),
    };
    final preferences = controller.getInterfacePreferences(preset);
    final loading = preset.isStandalone && coldStart;
    final profile = InterfaceWindowProfile(
      size: loading ? sizes.$2 : sizes.$1,
      minimumSize: loading
          ? sizes.$2
          : preset.isStandalone
          ? sizes.$1
          : const Size(720, 480),
      resizable:
          !preset.isStandalone ||
          !loading &&
              (preferences['resizable'] ?? preferences['resizableWindow']) ==
                  true,
      alwaysOnTop:
          (preferences['alwaysOnTop'] ?? preferences['topMost']) == true,
    );
    return loading ? profile : _studioProfile(controller, preset, profile);
  }

  static InterfaceWindowProfile _studioProfile(
    OrionController controller,
    InterfacePreset preset,
    InterfaceWindowProfile original,
  ) {
    if (!const {
      InterfacePreset.synapseV3,
      InterfacePreset.synapseBlue,
      InterfacePreset.synapseX,
      InterfacePreset.synapse2017,
    }.contains(preset)) {
      return original;
    }
    final window = SynapseThemeCatalog.current(
      controller,
      preset,
    ).window('main');
    if (window.width == null && window.height == null) return original;
    final descriptor = SynapseThemeCatalog.windows(
      preset,
    ).firstWhere((w) => w.id == 'main');
    final minimum = descriptor.minimumSize;
    return InterfaceWindowProfile(
      size: Size(
        (window.width ?? original.size.width).clamp(minimum.width, 4096),
        (window.height ?? original.size.height).clamp(minimum.height, 2160),
      ),
      minimumSize: minimum,
      resizable: original.resizable,
      alwaysOnTop: original.alwaysOnTop,
    );
  }
}
