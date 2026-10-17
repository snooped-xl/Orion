/// Interface names retained from Orion's original selector.
/// The selected preset configures this native Flutter workspace.
enum InterfacePreset {
  orion,
  synapseV3,
  synapse2017,
  synapseBlue,
  synapseX,
  rc7,
  krnl,
  calamari,
  awp,
  xeno,
  zenithV2,
}

extension InterfacePresetDetails on InterfacePreset {
  String get label => switch (this) {
    InterfacePreset.orion => 'Orion',
    InterfacePreset.synapseV3 => 'Synapse V3',
    InterfacePreset.synapse2017 => 'Synapse OG',
    InterfacePreset.synapseBlue => 'Synapse Blue',
    InterfacePreset.synapseX => 'Synapse X',
    InterfacePreset.rc7 => 'RC7',
    InterfacePreset.krnl => 'KRNL',
    InterfacePreset.calamari => 'Calamari',
    InterfacePreset.awp => 'AWP',
    InterfacePreset.xeno => 'Xeno',
    InterfacePreset.zenithV2 => 'Zenith V2',
  };

  /// Original selection identifiers, separate from their displayed names.
  String get sourceTag => switch (this) {
    InterfacePreset.orion => 'Orion',
    InterfacePreset.synapseV3 => 'SynapseV3',
    InterfacePreset.synapse2017 => 'Synapse2017',
    InterfacePreset.synapseBlue => 'SynapseBlue',
    InterfacePreset.synapseX => 'SynapseX',
    InterfacePreset.rc7 => 'RC7',
    InterfacePreset.krnl => 'Krnl',
    InterfacePreset.calamari => 'Calamari',
    InterfacePreset.awp => 'AWP',
    InterfacePreset.xeno => 'Xeno',
    InterfacePreset.zenithV2 => 'ZenithV2',
  };

  bool get isStandalone => const {
    InterfacePreset.synapseV3,
    InterfacePreset.synapseBlue,
    InterfacePreset.synapseX,
    InterfacePreset.synapse2017,
    InterfacePreset.krnl,
    InterfacePreset.calamari,
    InterfacePreset.awp,
    InterfacePreset.xeno,
    InterfacePreset.zenithV2,
  }.contains(this);

  static const available = [
    InterfacePreset.orion,
    InterfacePreset.synapseV3,
    InterfacePreset.synapseBlue,
    InterfacePreset.synapseX,
    InterfacePreset.synapse2017,
    InterfacePreset.zenithV2,
    InterfacePreset.awp,
    InterfacePreset.xeno,
    InterfacePreset.krnl,
    InterfacePreset.calamari,
  ];
}
