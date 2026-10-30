import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/monaco_editor_service.dart';
import '../state/orion_controller.dart';
import '../theme/orion_theme.dart';
import 'orion_overlay.dart';

/// One live client selection is shared by every Orion interface and window.
Future<void> showBridgeClientManager(
  BuildContext context, {
  required OrionController controller,
  MonacoEditorService? editorService,
}) async {
  const owner = 'bridge-client-manager';
  try {
    await editorService?.freezeForOverlay(owner: owner);
    if (!context.mounted) return;
    final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => OrionOverlayTheme(
        controller: controller,
        builder: (context) => Dialog(
          key: const ValueKey('bridge-client-manager'),
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(10),
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
          ),
          child: OrionOverlaySurface(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(10),
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 540,
                maxHeight: math.max(
                  160,
                  MediaQuery.sizeOf(context).height - 32,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 10, 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.devices_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Client manager',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close client manager',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: BridgeClientManagerPanel(controller: controller),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await Navigator.of(context, rootNavigator: true).push(route);
    // The native view must stay behind the dialog during its reverse animation.
    await route.completed;
  } finally {
    editorService?.setObscured(false, owner: owner);
  }
}

/// Shrink-wrapped for source UIs with their own native Clients window.
class BridgeClientManagerPanel extends StatefulWidget {
  const BridgeClientManagerPanel({super.key, required this.controller});
  final OrionController controller;

  @override
  State<BridgeClientManagerPanel> createState() =>
      _BridgeClientManagerPanelState();
}

class _BridgeClientManagerPanelState extends State<BridgeClientManagerPanel> {
  bool _busy = false;
  String? _feedback;
  bool _failed = false;
  OrionController get c => widget.controller;

  Future<void> _setupAction(String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    String? feedback;
    var failed = false;
    try {
      if (action == 'loader') {
        await Clipboard.setData(ClipboardData(text: c.bridgeLoader));
        feedback = c.usesNativeExecutor
            ? 'Native executor connection info copied'
            : 'Loader copied';
      } else {
        if (c.usesNativeExecutor) {
          feedback = 'Orion Bridge script is only used on Windows and Linux';
          failed = true;
        } else if (action == 'copy') {
          final source = await c.loadBridgeScript();
          if (!mounted) return;
          await Clipboard.setData(ClipboardData(text: source));
          feedback = 'Orion Bridge.lua copied';
        } else if (await c.saveBridgeScript()) {
          feedback = 'Orion Bridge.lua saved';
        }
      }
    } on Object catch (error) {
      feedback =
          'Could not ${action == 'save' ? 'save' : 'copy'} bridge: $error';
      failed = true;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _feedback = feedback;
          _failed = failed;
        });
      }
    }
  }

  Future<void> _retryBridge() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final listening = await c.initializeBridge();
      if (mounted) {
        setState(() {
          _feedback = c.usesRelapseSupport
              ? 'Relapse support is active'
              : listening
              ? 'Bridge ready'
              : 'Could not start the bridge';
          _failed = !listening;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _feedback = c.usesRelapseSupport
              ? 'Could not connect to Relapse: $error'
              : 'Could not start bridge: $error';
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OrionOverlayTheme(
    controller: c,
    builder: (context) {
      final theme = Theme.of(context), scheme = theme.colorScheme;
      final colors = OrionColors.of(context);
      final clients = c.bridgeClients;
      final selected = c.bridgeTargetAll
          ? clients.length
          : clients
                .where(
                  (client) =>
                      c.selectedBridgeClients.contains(client.identifier),
                )
                .length;
      final backend = c.usesRelapseSupport
          ? 'Relapse'
          : c.usesNativeExecutor
          ? (c.detectedNativeExecutor ?? 'Executor')
          : 'Bridge';
      final status = c.bridgeError != null
          ? '$backend unavailable'
          : c.usesRelapseSupport && c.relapseReady
          ? 'Connected · ready'
          : c.usesRelapseSupport && c.bridgeConnected
          ? 'Connected · waiting for game'
          : clients.isNotEmpty
          ? '${clients.length} connected'
          : c.bridgeListening
          ? (c.usesNativeExecutor
                ? 'Scanning local clients'
                : c.usesRelapseSupport
                ? 'Waiting for Relapse'
                : 'Waiting for clients')
          : '$backend offline';
      return Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: clients.isNotEmpty ? scheme.primary : scheme.outline,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(status, style: theme.textTheme.labelLarge),
                ),
                Text(
                  c.usesRelapseSupport
                      ? 'Relapse support'
                      : c.usesNativeExecutor
                      ? (Platform.isMacOS
                            ? 'macOS Bridge'
                            : c.detectedNativeExecutor ??
                                  (c.nativeExecutorPreference == 'auto'
                                      ? 'Auto executor'
                                      : c.nativeExecutorPreference == 'macsploit'
                                      ? 'MacSploit'
                                      : 'Opiumware'))
                      : 'Orion Bridge',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (c.bridgeError case final String error) ...[
              const SizedBox(height: 10),
              Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            if (c.usesNativeExecutor && !Platform.isMacOS) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('native-executor-selector'),
                initialValue: c.nativeExecutorPreference,
                decoration: const InputDecoration(
                  labelText: 'Executor',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'auto',
                    child: Text('Auto-detect'),
                  ),
                  DropdownMenuItem(
                    value: 'macsploit',
                    child: Text('MacSploit'),
                  ),
                  const DropdownMenuItem(
                    value: 'opiumware',
                    child: Text('Opiumware'),
                  ),
                  if (Platform.isMacOS)
                    const DropdownMenuItem(
                      value: 'helios',
                      child: Text('Helios'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) c.setNativeExecutorPreference(value);
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const ValueKey('native-port-selector'),
                initialValue: c.nativePortPreference?.toString() ?? 'auto',
                decoration: const InputDecoration(
                  labelText: 'Port',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'auto',
                    child: Text('Auto port'),
                  ),
                  for (final port in c.availableNativePorts)
                    DropdownMenuItem(value: '$port', child: Text('$port')),
                ],
                onChanged: (value) => c.setNativePortPreference(
                  value == null || value == 'auto' ? null : int.parse(value),
                ),
              ),
            ],
            if (c.usesNativeExecutor)
              Container(
                key: ValueKey(
                  'native-port-description-${c.nativePortPreference ?? 'auto'}',
                ),
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.stateFill(.07, base: colors.elevated),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  c.nativePortPreference == null
                      ? 'Available ports: ${c.availableNativePorts.join(', ')}'
                      : 'Pinned to localhost:${c.nativePortPreference}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (!c.bridgeListening ||
                c.bridgeError != null ||
                (c.usesRelapseSupport && !c.bridgeConnected))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('bridge-retry'),
                  onPressed: _busy ? null : _retryBridge,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(
                    c.usesNativeExecutor
                        ? 'Retry executor scan'
                        : c.usesRelapseSupport
                        ? 'Retry Relapse'
                        : 'Retry bridge',
                  ),
                ),
              ),
            if (!c.usesNativeExecutor && !c.usesRelapseSupport) ...[
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                key: const ValueKey('bridge-target-mode'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('All clients'),
                    icon: Icon(Icons.select_all_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Selected'),
                    icon: Icon(Icons.checklist_rounded, size: 18),
                  ),
                ],
                selected: {c.bridgeTargetAll},
                onSelectionChanged: (value) =>
                    c.setBridgeTargetAll(value.single),
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                c.bridgeTargetAll
                    ? 'Execute sends to every connected client.'
                    : '$selected of ${clients.length} selected for Execute.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (clients.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colors.chrome(colors.elevated, role: 'elevated'),
                  border: colors.transparentSurfaces
                      ? Border.all(color: colors.outline(.35), width: .67)
                      : null,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(6),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.devices_other_rounded,
                      size: 28,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No clients connected',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.usesRelapseSupport
                          ? 'Start Relapse on Linux. Orion watches ${c.relapseSocketPath} and connects automatically.'
                          : c.usesNativeExecutor
                          ? c.usesHelios
                                ? 'Helios provides execution over its local WebSocket bridge. Choose a specific listening port or leave the port on Auto.'
                                : 'Choose Auto-detect or select MacSploit or Opiumware above. Auto-detect prefers MacSploit; port can be selected explicitly or left on Auto port.'
                          : 'Run Orion Bridge in your executor to connect.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else if (c.usesNativeExecutor)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.stateFill(.09, base: colors.elevated),
                  border: colors.transparentSurfaces
                      ? Border.all(color: colors.outline(.35), width: .67)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  c.detectedNativeExecutor == null
                      ? Platform.isMacOS
                            ? 'Waiting for Helios, MacSploit, or Opiumware on their localhost bridge ports.'
                            : c.nativeExecutorPreference == 'opiumware'
                            ? 'Waiting for Opiumware on localhost ports 8392–8397.'
                            : 'Waiting for MacSploit (5553–5563) or Opiumware (8392–8397).'
                      : 'Detected ${c.detectedNativeExecutor}. Execution uses its first responsive port unless you choose a specific port above.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else if (c.usesRelapseSupport)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.stateFill(.09, base: colors.elevated),
                  border: colors.transparentSurfaces
                      ? Border.all(color: colors.outline(.35), width: .67)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.relapseReady
                          ? 'Relapse is ready for scripts.'
                          : 'Relapse is connected and waiting for a game session.',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.relapseOutputCaptureActive
                          ? 'Luau output is being forwarded to the Orion console.'
                          : 'Output capture is starting. Socket: ${c.relapseSocketPath}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              for (final client in clients) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color:
                        (c.bridgeTargetAll ||
                            c.selectedBridgeClients.contains(client.identifier))
                        ? colors.stateFill(.09, base: colors.elevated)
                        : colors.chrome(colors.elevated, role: 'elevated'),
                    border: colors.transparentSurfaces
                        ? Border.all(color: colors.outline(.35), width: .67)
                        : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value:
                            c.bridgeTargetAll ||
                            c.selectedBridgeClients.contains(client.identifier),
                        onChanged: (value) => c.setBridgeClientSelected(
                          client.identifier,
                          value ?? false,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                client.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${client.transport} · ${client.identifier}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Disconnect ${client.username}',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.link_off_rounded, size: 18),
                        onPressed: () =>
                            c.disconnectBridgeClient(client.identifier),
                      ),
                      const SizedBox(width: 3),
                    ],
                  ),
                ),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: c.disconnectAllBridgeClients,
                  icon: const Icon(Icons.link_off_rounded, size: 16),
                  label: const Text('Disconnect all'),
                ),
              ),
            ],
            const SizedBox(height: 10),
            ExpansionTile(
              key: const ValueKey('bridge-setup'),
              initiallyExpanded: clients.isEmpty,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 3, bottom: 4),
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                c.usesRelapseSupport
                    ? 'Relapse connection'
                    : 'Connect a client',
                style: theme.textTheme.titleSmall,
              ),
              leading: const Icon(Icons.add_link_rounded, size: 20),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    c.usesRelapseSupport
                        ? 'Orion connects to Relapse through its local Unix socket, sends scripts, and forwards captured output. Turn off Relapse support to use Orion Bridge again.'
                        : c.usesNativeExecutor
                        ? Platform.isMacOS
                              ? 'macOS Bridge detects Helios, MacSploit, or Opiumware and sends scripts through the matching local protocol. No separate Helios UI is used.'
                              : 'Native executor mode detects MacSploit (5553–5563) or Opiumware (8392–8397), then sends scripts to the selected or first responsive port. No Orion Bridge script is needed.'
                        : 'Copy the loader or full script and run it in each executor. Clients appear here automatically.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (!c.usesNativeExecutor && !c.usesRelapseSupport)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('bridge-copy-loader'),
                        onPressed: _busy ? null : () => _setupAction('loader'),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy loader'),
                      ),
                      FilledButton.tonalIcon(
                        key: const ValueKey('bridge-copy-script'),
                        onPressed: _busy ? null : () => _setupAction('copy'),
                        icon: const Icon(Icons.code_rounded, size: 16),
                        label: const Text('Copy script'),
                      ),
                      TextButton.icon(
                        key: const ValueKey('bridge-save-script'),
                        onPressed: _busy ? null : () => _setupAction('save'),
                        icon: const Icon(Icons.save_alt_rounded, size: 16),
                        label: const Text('Save script'),
                      ),
                    ],
                  ),
              ],
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (_feedback case final String message)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _failed ? scheme.error : scheme.primary,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
