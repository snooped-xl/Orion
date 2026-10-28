import 'package:flutter/material.dart';

import '../models/auto_update_models.dart';
import '../state/orion_controller.dart';
import '../theme/orion_theme.dart';
import 'common.dart';
import 'orion_logo.dart';
import 'orion_overlay.dart';

/// Interactive modal prompting the user when a newer release of Orion is detected.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.controller,
    required this.release,
  });

  final OrionController controller;
  final OrionRelease release;

  /// Convenience helper to show the dialog with Orion overlay theming.
  static Future<void> show(BuildContext context, {
    required OrionController controller,
    required OrionRelease release,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OrionOverlayTheme(
        controller: controller,
        builder: (_) => UpdateDialog(
          controller: controller,
          release: release,
        ),
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _updating = false;
  String? _localError;

  OrionController get c => widget.controller;
  OrionRelease get release => widget.release;

  Future<void> _startUpdate() async {
    setState(() {
      _updating = true;
      _localError = null;
    });

    try {
      await c.applyPendingUpdate(release);
    } catch (e) {
      if (mounted) {
        setState(() {
          _updating = false;
          _localError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    final status = c.updateStatus;
    final highlights = release.changelogHighlights;

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: OrionOverlaySurface(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with logo and versions
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const OrionLogo(size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Update available: ${release.tagName}',
                          style: OrionType.sectionTitle,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Current version: v${c.autoUpdate.currentVersion}',
                          style: OrionType.metadata.copyWith(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Error display if failed
              if (_localError != null || status.phase == AutoUpdatePhase.error) ...[
                SurfaceCard(
                  radius: 12,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, size: 18, color: colors.readablePeach),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _localError ?? status.errorMessage ?? 'Update failed',
                          style: OrionType.metadata.copyWith(color: colors.readablePeach),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Changelog highlights if available
              if (!_updating && highlights.isNotEmpty) ...[
                SurfaceCard(
                  radius: 12,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What’s new in ${release.tagName}:',
                        style: OrionType.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.readableAccent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final item in highlights)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('• ', style: TextStyle(color: colors.readableAccent)),
                              Expanded(
                                child: Text(
                                  item,
                                  style: OrionType.metadata.copyWith(color: colors.ink),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Progress bar during download / verification
              if (_updating) ...[
                SurfaceCard(
                  radius: 12,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            status.phase == AutoUpdatePhase.verifying
                                ? 'Verifying payload (SHA-256)...'
                                : status.phase == AutoUpdatePhase.readyToRestart
                                    ? 'Restarting Orion...'
                                    : 'Downloading update...',
                            style: OrionType.body.copyWith(fontWeight: FontWeight.w500),
                          ),
                          if (status.phase == AutoUpdatePhase.downloading)
                            Text(
                              '${(status.progress * 100).round()}%',
                              style: OrionType.metadata.copyWith(color: colors.readableAccent),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: status.phase == AutoUpdatePhase.verifying ||
                                status.phase == AutoUpdatePhase.readyToRestart
                            ? null
                            : status.progress > 0 ? status.progress : null,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      if (status.totalBytes > 0 && status.phase == AutoUpdatePhase.downloading) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${(status.receivedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / ${(status.totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                          style: OrionType.metadata.copyWith(color: colors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Bottom control bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Auto-update toggle checkbox
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: c.autoUpdateEnabled,
                          onChanged: _updating
                              ? null
                              : (value) => c.setAutoUpdateEnabled(value ?? true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Check automatically',
                        style: OrionType.metadata.copyWith(color: colors.muted),
                      ),
                    ],
                  ),

                  // Action buttons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_updating)
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Remind me later'),
                        ),
                      if (!_updating) const SizedBox(width: 8),
                      FilledButton.icon(
                        key: const ValueKey('update-dialog-confirm'),
                        onPressed: _updating ? null : _startUpdate,
                        icon: const Icon(Icons.system_update_rounded, size: 16),
                        label: Text(_updating ? 'Updating...' : 'Update & Restart'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
