import 'package:flutter/material.dart';

import '../models/interface_preset.dart';
import '../services/synapse_theme_catalog.dart';
import '../state/orion_controller.dart';
import '../theme/orion_theme.dart';
import 'synapse_theme_surface.dart';
import 'orion_glass.dart';

/// Applies an advanced layer to the real Expressive controls. Local colors
/// reach controls which deliberately paint their own Material surfaces.
class OrionStudioLayer extends StatelessWidget {
  const OrionStudioLayer({
    super.key,
    required this.controller,
    required this.elementId,
    required this.child,
  });

  final OrionController controller;
  final String elementId;
  final Widget child;

  @override
  Widget build(BuildContext context) => SynapseThemeElement(
    controller: controller,
    preset: InterfacePreset.orion,
    windowId: 'main',
    elementId: elementId,
    child: Builder(
      builder: (context) {
        final style = SynapseThemeElementStyleScope.maybeOf(context);
        final document = SynapseThemeCatalog.current(
          controller,
          InterfacePreset.orion,
        );
        final theme = Theme.of(context);
        final c = OrionColors.of(context);
        final image =
            style?.image?.isValid == true && style!.image!.opacity > 0;
        final fill = image
            ? Colors.transparent
            : style?.fill == null
            ? null
            : Color(style!.fill!);
        final ink = style?.foreground == null
            ? null
            : Color(style!.foreground!);
        final border = style?.border == null ? null : Color(style!.border!);
        final colors = OrionColors(
          background: fill ?? c.background,
          panel: fill ?? c.panel,
          elevated: fill ?? c.elevated,
          editorColor: fill ?? c.editorColor,
          border: border ?? c.border,
          muted: ink ?? c.muted,
          ink: ink ?? c.ink,
          accent: c.accent,
          lavender: c.lavender,
          peach: c.peach,
          backgroundGradient: fill != null ? null : c.backgroundGradient,
          outlineStrength: border == null ? c.outlineStrength : 1,
          surfaceTint: fill != null ? 0 : c.surfaceTint,
          transparentSurfaces: image || (fill == null && c.transparentSurfaces),
          glassEnabled: c.glassEnabled,
          opaqueSurfaceRoles: fill != null ? const {} : c.opaqueSurfaceRoles,
        );
        ButtonStyle fontStyle(ButtonStyle? original) {
          final previous = original?.textStyle;
          return (original ?? const ButtonStyle()).copyWith(
            textStyle: WidgetStateProperty.resolveWith(
              (states) =>
                  (previous?.resolve(states) ??
                          theme.textTheme.labelLarge ??
                          const TextStyle())
                      .copyWith(fontFamily: document.fontFamily),
            ),
          );
        }

        return Theme(
          data: theme.copyWith(
            extensions: [
              ...theme.extensions.values.where((e) => e is! OrionColors),
              colors,
            ],
            textTheme: theme.textTheme.apply(
              fontFamily: document.fontFamily,
              bodyColor: ink,
              displayColor: ink,
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: fontStyle(theme.filledButtonTheme.style),
            ),
            textButtonTheme: TextButtonThemeData(
              style: fontStyle(theme.textButtonTheme.style),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: fontStyle(theme.outlinedButtonTheme.style),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: fontStyle(theme.elevatedButtonTheme.style),
            ),
            segmentedButtonTheme: SegmentedButtonThemeData(
              style: fontStyle(theme.segmentedButtonTheme.style),
              selectedIcon: theme.segmentedButtonTheme.selectedIcon,
            ),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(fontFamily: document.fontFamily, color: ink),
            child: IconTheme.merge(
              data: IconThemeData(color: ink),
              child:
                  colors.glassEnabled &&
                      (elementId == 'titleBar' || elementId == 'sidebar')
                  ? OrionGlassSurface(
                      radius: elementId == 'titleBar' ? 20 : 24,
                      // The window owns one continuous optical sheet. These
                      // layout layers inherit it instead of adding new rims.
                      materialOpacity: 0,
                      child: child,
                    )
                  : child,
            ),
          ),
        );
      },
    ),
  );
}
