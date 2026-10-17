import 'dart:math' as math;
import 'dart:ui';

/// Positions a source-sized window on the monitor containing its previous centre.
/// Very small work areas constrain companion windows so their Close control stays
/// reachable; normal displays retain the exact source dimensions.
Rect ogWindowBounds({
  required Rect anchor,
  required Size size,
  Iterable<Rect> workAreas = const [],
}) {
  final areas = workAreas
      .where((area) => area.width > 0 && area.height > 0)
      .toList();
  if (areas.isEmpty) {
    return Rect.fromCenter(
      center: anchor.center,
      width: size.width,
      height: size.height,
    );
  }
  final area = areas.firstWhere(
    (area) => area.contains(anchor.center),
    orElse: () => areas.reduce(
      (a, b) =>
          (a.center - anchor.center).distanceSquared <=
              (b.center - anchor.center).distanceSquared
          ? a
          : b,
    ),
  );
  final fitted = Size(
    math.min(size.width, area.width),
    math.min(size.height, area.height),
  );
  final proposed = anchor.center - Offset(fitted.width / 2, fitted.height / 2);
  return Rect.fromLTWH(
    proposed.dx.clamp(area.left, area.right - fitted.width),
    proposed.dy.clamp(area.top, area.bottom - fitted.height),
    fitted.width,
    fitted.height,
  );
}
