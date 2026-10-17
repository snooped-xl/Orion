import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/interface_preset.dart';
import '../models/synapse_studio_theme.dart';
import '../services/synapse_theme_catalog.dart';
import '../state/orion_controller.dart';
import 'selected_builder.dart';

/// Explicit legacy controls can read this scope instead of ignoring a Studio
/// override through their own hard-coded ButtonStyle/TextStyle values.
class SynapseThemeElementStyleScope extends InheritedWidget {
  const SynapseThemeElementStyleScope({
    super.key,
    required super.child,
    this.style,
    this.fontFamily,
  });
  final SynapseStudioElement? style;
  final String? fontFamily;
  static SynapseStudioElement? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SynapseThemeElementStyleScope>()
      ?.style;
  static String? fontFamilyOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SynapseThemeElementStyleScope>()
      ?.fontFamily;
  @override
  bool updateShouldNotify(SynapseThemeElementStyleScope oldWidget) =>
      !identical(style, oldWidget.style) || fontFamily != oldWidget.fontFamily;
}

class SynapseThemeSurface extends StatelessWidget {
  const SynapseThemeSurface({
    super.key,
    required this.controller,
    required this.preset,
    required this.windowId,
    required this.child,
  });
  final OrionController controller;
  final InterfacePreset preset;
  final String windowId;
  final Widget child;
  @override
  Widget build(BuildContext context) => SelectedBuilder(
    listenable: controller,
    select: () => SynapseThemeCatalog.current(controller, preset),
    child: child,
    builder: (context, child) {
      final document = SynapseThemeCatalog.current(controller, preset);
      final window = document.window(windowId);
      Widget result = Stack(
        fit: StackFit.passthrough,
        children: [
          if (window.background?.isValid == true)
            Positioned.fill(
              child: IgnorePointer(child: _image(window.background!)),
            ),
          child!,
          if (window.overlay?.isValid == true)
            Positioned.fill(
              child: IgnorePointer(child: _image(window.overlay!)),
            ),
        ],
      );
      final family = document.fontFamily;
      if (family != null) {
        final theme = Theme.of(context);
        result = Theme(
          data: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: family),
            primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: family),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(fontFamily: family),
            child: result,
          ),
        );
      }
      return SynapseThemeElementStyleScope(fontFamily: family, child: result);
    },
  );
}

class SynapseThemeElement extends StatelessWidget {
  const SynapseThemeElement({
    super.key,
    required this.controller,
    required this.preset,
    required this.windowId,
    required this.elementId,
    required this.child,
  });
  final OrionController controller;
  final InterfacePreset preset;
  final String windowId, elementId;
  final Widget child;
  @override
  Widget build(BuildContext context) => SelectedBuilder(
    listenable: controller,
    select: () => SynapseThemeCatalog.current(controller, preset),
    child: child,
    builder: (context, child) {
      final document = SynapseThemeCatalog.current(controller, preset);
      final element = document.window(windowId).elements[elementId];
      Widget result = SynapseThemeElementStyleScope(
        style: element,
        fontFamily: document.fontFamily,
        child: child!,
      );
      if (element == null) return result;
      if (element.foreground != null) {
        result = DefaultTextStyle.merge(
          style: TextStyle(color: Color(element.foreground!)),
          child: IconTheme.merge(
            data: IconThemeData(color: Color(element.foreground!)),
            child: result,
          ),
        );
      }
      if (element.fill != null ||
          element.border != null ||
          element.radius != null ||
          element.image?.isValid == true) {
        result = DecoratedBox(
          decoration: BoxDecoration(
            color: element.fill == null ? null : Color(element.fill!),
            border: element.border == null
                ? null
                : Border.all(color: Color(element.border!)),
            borderRadius: element.radius == null
                ? null
                : BorderRadius.circular(element.radius!),
          ),
          child: elementId != 'logo' && element.image?.isValid == true
              ? Stack(
                  fit: StackFit.passthrough,
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(child: _image(element.image!)),
                    ),
                    result,
                  ],
                )
              : result,
        );
        if (element.radius != null) {
          result = ClipRRect(
            borderRadius: BorderRadius.circular(element.radius!),
            child: result,
          );
        }
      }
      if (element.width != null || element.height != null) {
        final sized = result;
        result = LayoutBuilder(
          builder: (context, constraints) {
            double? bound(double? value, double maximum) => value == null
                ? null
                : math
                      .min(value, maximum.isFinite ? maximum : value)
                      .clamp(0, 4096)
                      .toDouble();
            return Align(
              alignment: Alignment.topLeft,
              widthFactor: 1,
              heightFactor: 1,
              child: SizedBox(
                width: bound(element.width, constraints.maxWidth),
                height: bound(element.height, constraints.maxHeight),
                child: sized,
              ),
            );
          },
        );
      }
      if (element.opacity < 1) {
        result = IgnorePointer(
          ignoring: element.opacity == 0,
          child: Opacity(opacity: element.opacity, child: result),
        );
      }
      if (element.x != 0 || element.y != 0) {
        result = Transform.translate(
          offset: Offset(element.x, element.y),
          child: result,
        );
      }
      return result;
    },
  );
}

class SynapseThemeLogo extends StatelessWidget {
  const SynapseThemeLogo({
    super.key,
    required this.controller,
    required this.preset,
    required this.windowId,
    required this.child,
    this.elementId = 'logo',
  });
  final OrionController controller;
  final InterfacePreset preset;
  final String windowId, elementId;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final image = SelectedBuilder(
      listenable: controller,
      select: () => SynapseThemeCatalog.current(controller, preset),
      child: child,
      builder: (context, fallback) {
        final window = SynapseThemeCatalog.current(
          controller,
          preset,
        ).window(windowId);
        final element = window.elements[elementId];
        final image = element?.image ?? window.logo;
        final result = image?.isValid == true
            ? _image(image!, fallback: fallback, cacheWidth: 1024)
            : fallback!;
        return element?.foreground == null
            ? result
            : ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Color(element!.foreground!),
                  BlendMode.srcIn,
                ),
                child: result,
              );
      },
    );
    final ancestor = context
        .findAncestorWidgetOfExactType<SynapseThemeElement>();
    if (ancestor?.elementId == elementId &&
        ancestor?.windowId == windowId &&
        ancestor?.preset == preset) {
      return image;
    }
    // The element handles geometry, paint and opacity. Its logo image is
    // rendered above exactly once, rather than as a second background layer.
    return SynapseThemeElement(
      controller: controller,
      preset: preset,
      windowId: windowId,
      elementId: elementId,
      child: image,
    );
  }
}

Widget _image(
  SynapseStudioImage image, {
  Widget? fallback,
  int cacheWidth = 2048,
}) {
  if (image.bytes == null) return fallback ?? const SizedBox.shrink();
  final fit = switch (image.fit) {
    'contain' => BoxFit.contain,
    'fill' => BoxFit.fill,
    'fitWidth' => BoxFit.fitWidth,
    'fitHeight' => BoxFit.fitHeight,
    'none' => BoxFit.none,
    'scaleDown' => BoxFit.scaleDown,
    _ => BoxFit.cover,
  };
  return Opacity(
    opacity: image.opacity,
    child: Image.memory(
      image.bytes!,
      fit: fit,
      gaplessPlayback: true,
      cacheWidth: cacheWidth,
      errorBuilder: (_, _, _) => fallback ?? const SizedBox.shrink(),
    ),
  );
}
