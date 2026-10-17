import 'package:flutter/material.dart';

import 'orion_theme.dart';

/// Carry the easy theme through surfaces without flattening Material's layers.
LinearGradient? orionSurfaceGradient(
  OrionColors colors, {
  Color? base,
  double blend = .24,
}) {
  final gradient = colors.backgroundGradient;
  if (gradient == null || colors.transparentSurfaces) return null;
  return LinearGradient(
    begin: gradient.begin,
    end: gradient.end,
    stops: gradient.stops,
    tileMode: gradient.tileMode,
    transform: gradient.transform,
    colors: [
      for (final color in gradient.colors)
        Color.lerp(base ?? colors.panel, color, blend)!,
    ],
  );
}
