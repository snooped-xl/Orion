import 'interface_preset.dart';

/// Separate source windows and the shared Material theme editors.
enum CompanionWindowKind {
  krnlOptions,
  xenoSettings,
  xenoScripts,
  xenoClients,
  synapseXOptions,
  synapseXHub,
  synapseXConsole,
  synapseOgSettings,
  synapseOgHub,
  synapseOgConsole,
  synapseV3Editor,
  orionThemeStudio,
  synapseV3ThemeStudio,
  synapseBlueThemeStudio,
  synapseXThemeStudio,
  synapseOgThemeStudio,
}

extension CompanionThemeStudioKind on CompanionWindowKind {
  InterfacePreset? get themeStudioPreset => switch (this) {
    CompanionWindowKind.orionThemeStudio => InterfacePreset.orion,
    CompanionWindowKind.synapseV3ThemeStudio => InterfacePreset.synapseV3,
    CompanionWindowKind.synapseBlueThemeStudio => InterfacePreset.synapseBlue,
    CompanionWindowKind.synapseXThemeStudio => InterfacePreset.synapseX,
    CompanionWindowKind.synapseOgThemeStudio => InterfacePreset.synapse2017,
    _ => null,
  };

  bool get isThemeStudio => themeStudioPreset != null;

  static CompanionWindowKind forPreset(InterfacePreset preset) =>
      switch (preset) {
        InterfacePreset.orion => CompanionWindowKind.orionThemeStudio,
        InterfacePreset.synapseV3 => CompanionWindowKind.synapseV3ThemeStudio,
        InterfacePreset.synapseBlue =>
          CompanionWindowKind.synapseBlueThemeStudio,
        InterfacePreset.synapseX => CompanionWindowKind.synapseXThemeStudio,
        InterfacePreset.synapse2017 => CompanionWindowKind.synapseOgThemeStudio,
        _ => throw ArgumentError.value(
          preset,
          'preset',
          'Theme Studio is unavailable for this interface',
        ),
      };
}

/// Shared contract for the primary workspace and its native companion engines.
/// A null host means an embedded widget fixture, with no desktop integration.
abstract interface class CompanionWindowHost {
  bool get isChildWindow;
  CompanionWindowKind? get kind;
  String? get documentId;

  Future<void> open(CompanionWindowKind kind, {String? documentId});
  Future<void> close();
  Future<void> closeAll();
  Future<void> focusMain();
  Future<void> returnToOrion();
  Future<void> updateOwnerWindow({
    bool? alwaysOnTop,
    bool? resizable,
    double? opacity,
  });
}
