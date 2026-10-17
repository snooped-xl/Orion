import 'dart:math';
import 'dart:typed_data';

import 'rain_effect_physics.dart';

/// Fixed-clock Flutter/Dart adaptation of Codrops' established glass rain.
/// Native GPU compositing consumes its bounded logical-pixel lens packet.
class OrionRainSimulation {
  OrionRainSimulation({
    required double width,
    required double height,
    Random? random,
  }) : physics = RainEffectPhysics(
         width: width,
         height: height,
         random: random,
         maxDrops: 120,
         maxBeads: _beadLimit(width, height),
         minRadius: 3.5,
         maxRadius: 6.5,
         motionScale: .55,
         spawnRate: 10,
       ) {
    physics.seed(
      beadCount: physics.maxBeads * 85 ~/ 100,
      dropCount: (width * height / 6500).round().clamp(40, 100),
    );
    _updatePacket();
  }

  final RainEffectPhysics physics;
  static const int stride = 8;
  static const int _stepMicroseconds = 16667;
  static const int _maxSteps = 8;
  int _accumulatorMicroseconds = 0;
  Float32List _packet = Float32List(0);

  double get width => physics.width;
  double get height => physics.height;

  static int _beadLimit(double width, double height) {
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      throw ArgumentError(
        'Rain surface dimensions must be finite and positive',
      );
    }
    return (width * height * .0018).clamp(360, 900).round();
  }

  /// [x, y, radiusX, radiusY, strength, kind, seed, trailLength] per row.
  /// Kind 0 is a stationary bead and kind 1 is a small sliding drop.
  /// Dry pixels remain transparent in the GPU pass; these are lens bounds.
  Float32List get packet => _packet;
  int get dropCount => _packet.length ~/ stride;

  /// Repositions existing lenses proportionally during animated window morphs.
  /// Their logical-pixel radii and seeded identities remain unchanged.
  void resize({required double width, required double height}) {
    physics.resize(width, height);
    _updatePacket();
  }

  void advance(Duration delta) {
    if (delta.inMicroseconds <= 0) return;
    _accumulatorMicroseconds = min(
      _accumulatorMicroseconds + delta.inMicroseconds,
      _stepMicroseconds * _maxSteps,
    );
    var changed = false;
    while (_accumulatorMicroseconds >= _stepMicroseconds) {
      physics.step(1);
      _accumulatorMicroseconds -= _stepMicroseconds;
      changed = true;
    }
    if (changed) _updatePacket();
  }

  void _updatePacket() {
    final result = Float32List(
      (physics.beads.length + physics.drops.length) * stride,
    );
    var i = 0;
    for (final bead in physics.beads) {
      result[i++] = bead.x;
      result[i++] = bead.y;
      result[i++] = bead.radius * (.9 + bead.seed * .1);
      result[i++] = bead.radius * (1 + bead.seed * .12);
      result[i++] = .8 + bead.seed * .2;
      result[i++] = 0;
      result[i++] = bead.seed;
      result[i++] = 0;
    }
    for (final drop in physics.drops) {
      result[i++] = drop.x;
      result[i++] = drop.y;
      result[i++] = drop.radius * (1 + drop.spreadX * .12);
      result[i++] = drop.radius * (1.1 + drop.spreadY * .18);
      result[i++] = .7 + drop.seed * .15;
      result[i++] = 1;
      result[i++] = drop.seed;
      result[i++] = min(18 + drop.seed * 28, drop.distanceTravelled);
    }
    _packet = result;
  }
}
