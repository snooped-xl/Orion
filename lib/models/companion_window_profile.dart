import 'package:flutter/services.dart';

import 'companion_window.dart';

/// Dimensions and ownership measured from the original WinForms/Avalonia and
/// Synapse Framework window declarations, rather than the editor's page size.
class CompanionWindowProfile {
  const CompanionWindowProfile(
    this.title,
    this.size, {
    this.minimumSize,
    this.resizable = true,
    this.owned = false,
    this.modal = false,
    this.skipTaskbar = false,
    this.cornerRadius = 0,
  });
  final String title;
  final Size size;
  final Size? minimumSize;
  final bool resizable, owned, modal, skipTaskbar;
  final double cornerRadius;

  static const themeStudioCornerRadius = 20.0;

  static CompanionWindowProfile forKind(CompanionWindowKind kind) =>
      switch (kind) {
        CompanionWindowKind.krnlOptions => const CompanionWindowProfile(
          'KRNL Options',
          Size(248, 153),
          resizable: false,
          owned: true,
          modal: true,
          skipTaskbar: true,
        ),
        CompanionWindowKind.xenoSettings => const CompanionWindowProfile(
          'Xeno Settings',
          Size(330, 270),
          resizable: false,
          skipTaskbar: true,
        ),
        CompanionWindowKind.xenoScripts => const CompanionWindowProfile(
          'Xeno Scripts',
          Size(300, 200),
          resizable: false,
          skipTaskbar: true,
        ),
        CompanionWindowKind.xenoClients => const CompanionWindowProfile(
          'Xeno Clients',
          Size(300, 200),
          resizable: false,
          owned: true,
          skipTaskbar: true,
        ),
        CompanionWindowKind.synapseXOptions => const CompanionWindowProfile(
          'Synapse X Options',
          Size(528, 460),
          minimumSize: Size(1, 1),
        ),
        CompanionWindowKind.synapseOgSettings => const CompanionWindowProfile(
          'Synapse Settings',
          Size(649, 705),
          minimumSize: Size(1, 1),
        ),
        CompanionWindowKind.synapseXHub => const CompanionWindowProfile(
          'Synapse X Script Hub',
          Size(612, 384),
          minimumSize: Size(1, 1),
        ),
        CompanionWindowKind.synapseOgHub => const CompanionWindowProfile(
          'Synapse Script Hub',
          Size(612, 384),
          minimumSize: Size(1, 1),
        ),
        CompanionWindowKind.synapseXConsole => const CompanionWindowProfile(
          'Synapse X Console',
          Size(520, 300),
          minimumSize: Size(1, 1),
        ),
        CompanionWindowKind.synapseOgConsole => const CompanionWindowProfile(
          'Synapse Console',
          Size(520, 300),
          minimumSize: Size(1, 1),
        ),
        CompanionWindowKind.synapseV3Editor => const CompanionWindowProfile(
          'Synapse V3 — Undocked editor',
          Size(720, 446),
          minimumSize: Size(480, 300),
        ),
        CompanionWindowKind.orionThemeStudio ||
        CompanionWindowKind.synapseV3ThemeStudio ||
        CompanionWindowKind.synapseBlueThemeStudio ||
        CompanionWindowKind.synapseXThemeStudio ||
        CompanionWindowKind.synapseOgThemeStudio =>
          const CompanionWindowProfile(
            'Theme Studio',
            Size(1180, 760),
            minimumSize: Size(800, 560),
            cornerRadius: themeStudioCornerRadius,
          ),
      };
}
