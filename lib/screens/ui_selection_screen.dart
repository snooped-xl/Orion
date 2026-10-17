import 'package:flutter/material.dart';
import '../widgets/orion_glass.dart';

import '../models/interface_preset.dart';
import '../state/orion_controller.dart';
import '../theme/orion_theme.dart';
import '../theme/orion_density.dart';
import '../widgets/interface_logo.dart';
import '../widgets/selected_builder.dart';

class UISelectionScreen extends StatefulWidget {
  final OrionController controller;
  final VoidCallback? onOpenWorkspace;
  final Future<void> Function(InterfacePreset)? onSelectInterface;

  const UISelectionScreen({
    super.key,
    required this.controller,
    this.onOpenWorkspace,
    this.onSelectInterface,
  });

  @override
  State<UISelectionScreen> createState() => _UISelectionScreenState();
}

class _UISelectionScreenState extends State<UISelectionScreen> {
  InterfacePreset? _opening;

  Future<void> _select(InterfacePreset preset) async {
    if (_opening != null) return;
    setState(() => _opening = preset);
    try {
      if (preset == InterfacePreset.orion &&
          !widget.controller.selectedInterface.isStandalone &&
          widget.onOpenWorkspace != null) {
        widget.onOpenWorkspace!();
      } else if (widget.onSelectInterface != null) {
        await widget.onSelectInterface!(preset);
      } else {
        widget.controller.setInterface(preset);
        await widget.controller.flushPersistence();
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) => SelectedBuilder(
    listenable: widget.controller,
    select: () =>
        (widget.controller.selectedInterface, widget.controller.reducedMotion),
    builder: (context, _) {
      final density = OrionDensity.of(context);
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('UI Selection', style: OrionType.pageTitle),
            const SizedBox(height: 4),
            Text(
              'Not all UIs are fully polished or finished. Checkmarks mean ready to use without known bugs, though the UI may not fully match the original.',
              style: OrionType.body.copyWith(
                color: OrionColors.of(context).muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 480
                    ? 3
                    : constraints.maxWidth >= 310
                    ? 2
                    : 1;
                const spacing = 10.0;
                final width =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  key: const ValueKey('interface-grid'),
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final preset in InterfacePresetDetails.available)
                      SizedBox(
                        key: ValueKey('interface-card-${preset.name}'),
                        width: width,
                        height: density.mix(115, 97),
                        child: _InterfaceChoice(
                          preset: preset,
                          selected: preset == InterfacePreset.orion
                              ? !widget
                                    .controller
                                    .selectedInterface
                                    .isStandalone
                              : widget.controller.selectedInterface == preset,
                          opening: _opening == preset,
                          enabled: _opening == null,
                          reducedMotion: widget.controller.reducedMotion,
                          onPressed: () => _select(preset),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

class _InterfaceChoice extends StatefulWidget {
  const _InterfaceChoice({
    required this.preset,
    required this.selected,
    required this.opening,
    required this.enabled,
    required this.reducedMotion,
    required this.onPressed,
  });

  final InterfacePreset preset;
  final bool selected, opening, enabled, reducedMotion;
  final VoidCallback onPressed;

  @override
  State<_InterfaceChoice> createState() => _InterfaceChoiceState();
}

class _InterfaceChoiceState extends State<_InterfaceChoice> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    final density = OrionDensity.of(context);
    final isOrion = widget.preset == InterfacePreset.orion;
    final actionLabel = widget.selected
        ? isOrion
              ? 'Open editor'
              : 'Open ${widget.preset.label}'
        : 'Use ${widget.preset.label}';
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: OrionGlassSurface(
        radius: 20,
        tint: colors.panel.withValues(alpha: .08),
        child: AnimatedContainer(
          duration: widget.reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.all(density.mix(12, 10)),
          decoration: BoxDecoration(
            color: _hovered
                ? colors.stateFill(.035)
                : colors.chrome(colors.panel, role: 'panel'),
            borderRadius: colors.glassEnabled
                ? BorderRadius.circular(20)
                : const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
            border: colors.glassEnabled
                ? null
                : Border.all(
                    color: widget.selected
                        ? colors.accent.withValues(alpha: .55)
                        : _hovered
                        ? colors.accent.withValues(alpha: .35)
                        : colors.outline(.35),
                  ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: density.mix(42, 40),
                child: Row(
                  children: [
                    if (widget.preset == InterfacePreset.awp)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: InterfaceLogo(preset: widget.preset, size: 44),
                        ),
                      ),
                    if (widget.preset != InterfacePreset.awp) ...[
                      InterfaceLogo(preset: widget.preset, size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.preset.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: OrionType.sectionTitle.copyWith(fontSize: 14),
                        ),
                      ),
                    ],
                    if (const {
                      InterfacePreset.orion,
                      InterfacePreset.synapseX,
                      InterfacePreset.synapse2017,
                      InterfacePreset.xeno,
                      InterfacePreset.awp,
                    }.contains(widget.preset)) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Ready to use',
                        child: Icon(
                          Icons.check_circle_rounded,
                          key: ValueKey(
                            'finished-interface-${widget.preset.name}',
                          ),
                          semanticLabel: 'Ready to use',
                          color: colors.readableAccent,
                          size: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              Semantics(
                label: actionLabel,
                excludeSemantics: true,
                button: true,
                enabled: widget.enabled,
                onTap: widget.enabled ? widget.onPressed : null,
                child: SizedBox(
                  height: density.mix(32, 30),
                  child: FilledButton.tonal(
                    key: ValueKey('select-interface-${widget.preset.name}'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: Size.zero,
                      backgroundColor: colors.chrome(
                        widget.selected
                            ? colors.accent.withValues(alpha: .18)
                            : colors.elevated,
                        role: 'elevated',
                      ),
                      foregroundColor: widget.selected
                          ? colors.readableAccent
                          : colors.ink,
                      side: colors.transparentSurfaces
                          ? BorderSide(color: colors.outline(.35), width: .67)
                          : BorderSide.none,
                      shape: colors.glassEnabled
                          ? null
                          : const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10),
                                bottomLeft: Radius.circular(10),
                                bottomRight: Radius.circular(2),
                              ),
                            ),
                      textStyle: OrionType.label.copyWith(
                        fontFamily: Theme.of(
                          context,
                        ).textTheme.labelLarge?.fontFamily,
                      ),
                    ),
                    onPressed: widget.enabled ? widget.onPressed : null,
                    child: widget.opening
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  widget.selected
                                      ? isOrion
                                            ? 'Open editor'
                                            : 'Open'
                                      : 'Use',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_outward_rounded, size: 14),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
