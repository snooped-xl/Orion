import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../state/orion_controller.dart';
import '../models/interface_preset.dart';
import '../services/synapse_theme_catalog.dart';
import '../services/monaco_editor_service.dart';
import '../theme/orion_surfaces.dart';
import '../theme/orion_theme.dart';
import 'orion_glass.dart';

/// Resolve the owner's Theme Control palette inside routes which outlive the
/// widget that opened them, including routes opened from a preserved interface.
class OrionOverlayTheme extends StatelessWidget {
  const OrionOverlayTheme({
    super.key,
    required this.controller,
    required this.builder,
  });

  final OrionController controller;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final reduced =
          controller.reducedMotion || MediaQuery.disableAnimationsOf(context);
      final brightness = switch (controller.themeMode) {
        ThemeMode.dark => Brightness.dark,
        ThemeMode.light => Brightness.light,
        ThemeMode.system => MediaQuery.platformBrightnessOf(context),
      };
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: AnimatedTheme(
          data: orionTheme(
            brightness,
            controller.orionTheme.accent,
            fontFamily: controller.selectedInterface == InterfacePreset.orion
                ? SynapseThemeCatalog.current(
                    controller,
                    InterfacePreset.orion,
                  ).fontFamily
                : null,
            reducedMotion: reduced,
            compactMode: controller.orionCompactMode,
            preferences: controller.orionTheme,
          ),
          duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: Builder(builder: builder),
        ),
      );
    },
  );
}

/// A fine-tuned elevated role is an exact color choice. Otherwise Easy theme's
/// gradient carries into overlays; Classic keeps its authored neutral gradient.
LinearGradient? orionOverlayGradient(OrionColors colors) {
  if (colors.glassEnabled || colors.opaqueSurfaceRoles.contains('elevated')) {
    return null;
  }
  if (colors.transparentSurfaces) return colors.backgroundGradient;
  return orionSurfaceGradient(colors, base: colors.elevated, blend: .3);
}

/// Readable popup chrome with the same palette and gradient as the workspace.
/// Set the containing Dialog's backgroundColor to Colors.transparent.
class OrionOverlaySurface extends StatelessWidget {
  const OrionOverlaySurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<OrionColors>();
    if (colors?.glassEnabled == true) {
      final radius = borderRadius.topLeft.x;
      Widget surface = OrionGlassSurface(
        radius: radius,
        materialOpacity: .45,
        tint: colors!.elevated.withValues(alpha: .14),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      );
      // Floating glass must frost the workspace underneath the route, not
      // leave other labels showing sharply through its own controls. This
      // samples only Orion's painted UI; it never captures the desktop.
      surface = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: ColoredBox(
            color: colors.elevated.withValues(alpha: .18),
            child: surface,
          ),
        ),
      );
      if (!OrionGlassScene.isActive(context)) {
        surface = OrionGlassScene(
          backdrop: OrionGlassBackdrop(
            tint: colors.background,
            authoredGradient: colors.backgroundGradient,
            useAuthoredBackground: true,
          ),
          reducedMotion: MediaQuery.disableAnimationsOf(context),
          child: surface,
        );
      }
      return KeyedSubtree(
        key: const ValueKey('orion-overlay-decoration'),
        child: surface,
      );
    }
    return AnimatedContainer(
      key: const ValueKey('orion-overlay-decoration'),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: BoxDecoration(
        color: colors?.elevated ?? theme.colorScheme.surfaceContainerHigh,
        gradient: colors == null ? null : orionOverlayGradient(colors),
        border: Border.all(
          color:
              colors?.outline(colors.transparentSurfaces ? .6 : .4) ??
              theme.colorScheme.outlineVariant,
          width: colors?.transparentSurfaces == true ? .67 : 1,
        ),
        borderRadius: borderRadius,
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// Wait through the reverse transition before restoring a native editor or
/// disposing a text controller owned by the caller.
Future<T?> showOrionDialog<T>(
  BuildContext context, {
  required OrionController controller,
  required WidgetBuilder builder,
  MonacoEditorService? editorService,
  bool barrierDismissible = true,
}) async {
  const owner = 'orion-themed-dialog';
  try {
    await editorService?.freezeForOverlay(owner: owner);
    if (!context.mounted) return null;
    final route = DialogRoute<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) =>
          OrionOverlayTheme(controller: controller, builder: builder),
    );
    final result = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    return result;
  } finally {
    editorService?.setObscured(false, owner: owner);
  }
}

/// AlertDialog's usual API, with one uninterrupted themed overlay surface.
class OrionAlertDialog extends StatelessWidget {
  const OrionAlertDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
  });
  final Widget title, content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(16),
    contentPadding: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    constraints: const BoxConstraints(maxWidth: 480),
    content: OrionOverlaySurface(
      child: SizedBox(
        width: 480,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.sizeOf(context).height -
                32 -
                MediaQuery.viewInsetsOf(context).vertical,
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DefaultTextStyle(
                  style:
                      Theme.of(context).dialogTheme.titleTextStyle ??
                      Theme.of(context).textTheme.titleLarge!,
                  child: title,
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: DefaultTextStyle(
                      style:
                          Theme.of(context).dialogTheme.contentTextStyle ??
                          Theme.of(context).textTheme.bodyMedium!,
                      child: content,
                    ),
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 6,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
