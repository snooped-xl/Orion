import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Material's spatial springs may overshoot; effects stay critically damped.
/// Values follow AndroidX ExpressiveMotionTokens v0_14_0. Finite durations
/// keep desktop page transitions predictable, including reduced motion.
abstract final class OrionMotion {
  static final Curve spatial = _SpringCurve(380, .8, .5);
  static final Curve spatialFast = _SpringCurve(800, .6, .3);
  static final Curve effects = _SpringCurve(1600, 1, .3);
  static const pageDuration = Duration(milliseconds: 500);
}

class _SpringCurve extends Curve {
  _SpringCurve(double stiffness, double damping, this.seconds)
    : simulation = SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: stiffness,
          ratio: damping,
        ),
        0,
        1,
        0,
      );

  final SpringSimulation simulation;
  final double seconds;

  @override
  double transformInternal(double t) => simulation.x(t * seconds);
}
