import 'package:flutter/material.dart';

import '../models/companion_window.dart';
import '../models/interface_preset.dart';
import '../screens/synapse_theme_studio.dart';
import '../state/orion_controller.dart';
import '../widgets/orion_overlay.dart';
import 'monaco_editor_service.dart';

/// Native engines own a separate Material window. Embedded widget hosts use a
/// contained editor route with the same draft/apply behavior.
Future<void> openThemeStudio(
  BuildContext context, {
  required OrionController controller,
  required InterfacePreset preset,
  MonacoEditorService? editorService,
}) async {
  final kind = CompanionThemeStudioKind.forPreset(preset);
  await editorService?.flush();
  if (!context.mounted) return;
  final host = controller.companionWindows;
  if (host != null) {
    await host.open(kind);
    return;
  }
  await showOrionDialog<void>(
    context,
    controller: controller,
    editorService: editorService,
    barrierDismissible: false,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 1180,
        height: 760,
        child: SynapseThemeStudioScreen(
          controller: controller,
          preset: preset,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    ),
  );
}

/// Source shells keep this alias while sharing the same generic editor.
Future<void> openSynapseThemeStudio(
  BuildContext context, {
  required OrionController controller,
  required InterfacePreset preset,
  MonacoEditorService? editorService,
}) => openThemeStudio(
  context,
  controller: controller,
  preset: preset,
  editorService: editorService,
);
