// Adapted from RainEffect by Lucas Bebber / Codrops (2015).
// https://github.com/codrops/RainEffect/blob/5270be663903883ae585858216b656120d8d4cd5/src/raindrops.js
// MIT license and adaptation notes: assets/effects/ATTRIBUTIONS.md.

import 'dart:math';

/// A bounded, renderer-independent adaptation of Codrops' rain-on-glass engine.
///
/// Keeps the original creeping momentum, shrinking, spread relaxation, daughter
/// droplets and area-based coalescence. Positions are logical pixels; momentum
/// retains upstream's pixels-per-reference-frame units. [step] accepts reference
/// frames so callers can drive it with a fixed clock instead of display FPS.
class RainEffectPhysics {
  RainEffectPhysics({
    required this.width,
    required this.height,
    Random? random,
    this.maxDrops = 60,
    this.maxBeads = 720,
    this.minRadius = 8,
    this.maxRadius = 15,
    this.motionScale = .2,
    this.spawnRate = 1,
  }) : random = random ?? Random() {
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      throw ArgumentError(
        'Rain surface dimensions must be finite and positive',
      );
    }
    if (maxDrops < 1 ||
        maxBeads < 1 ||
        minRadius <= 0 ||
        maxRadius <= minRadius ||
        !minRadius.isFinite ||
        !maxRadius.isFinite ||
        !motionScale.isFinite ||
        motionScale <= 0 ||
        !spawnRate.isFinite ||
        spawnRate <= 0) {
      throw ArgumentError('Invalid rain simulation limits');
    }
  }

  double width;
  double height;
  final Random random;
  final int maxDrops;
  final int maxBeads;
  final double minRadius;
  final double maxRadius;
  final double motionScale;
  final double spawnRate;
  final List<RainEffectDrop> drops = [];
  final List<RainEffectBead> beads = [];

  double _beadAccumulator = 0;
  int _beadWriteIndex = 0;

  double get _areaMultiplier => sqrt(width * height / (1024 * 768));
  double _between(double a, double b) => a + (b - a) * random.nextDouble();

  /// Starts with an already wet, irregular pane instead of a uniform grid.
  void seed({required int beadCount, required int dropCount}) {
    for (var i = 0; i < min(beadCount, maxBeads); i++) {
      addBead(
        RainEffectBead(
          x: random.nextDouble() * width,
          y: random.nextDouble() * height,
          radius: 1 + pow(random.nextDouble(), 2).toDouble() * 2.3,
          seed: random.nextDouble(),
        ),
      );
    }
    for (var i = 0; i < min(dropCount, maxDrops); i++) {
      final drop = _newRainDrop();
      // Existing drops have settled; newly arriving drops briefly spread out.
      drop.spreadX = .04 * random.nextDouble();
      drop.spreadY = .12 * random.nextDouble();
      drop.radius = _between(minRadius + 1, maxRadius);
      drop.momentum = _between(1.8, 2.9);
      drop.distanceTravelled = _between(10, 85);
      addDrop(drop);
    }
  }

  RainEffectDrop _newRainDrop() {
    // The cubic distribution in RainEffect creates many modest drops and an
    // occasional larger lens, rather than an evenly populated size range.
    final radius =
        minRadius +
        pow(random.nextDouble(), 3).toDouble() * (maxRadius - minRadius);
    return RainEffectDrop(
      x: random.nextDouble() * width,
      y: _between(-.1 * height, .95 * height),
      radius: radius,
      momentum: 1 + (radius - minRadius) * .1 + random.nextDouble() * 2,
      spreadX: 1.5,
      spreadY: 1.5,
      seed: random.nextDouble(),
    );
  }

  bool addDrop(RainEffectDrop drop) {
    if (drops.length >= maxDrops || !drop.isFinite || drop.radius <= 0) {
      return false;
    }
    drops.add(drop);
    return true;
  }

  void addBead(RainEffectBead bead) {
    if (!bead.x.isFinite ||
        !bead.y.isFinite ||
        !bead.radius.isFinite ||
        !bead.seed.isFinite ||
        bead.radius <= 0) {
      return;
    }
    if (beads.length < maxBeads) {
      beads.add(bead);
    } else {
      _beadWriteIndex %= beads.length;
      beads[_beadWriteIndex] = bead;
      _beadWriteIndex++;
    }
  }

  void resize(double nextWidth, double nextHeight) {
    if (!nextWidth.isFinite ||
        !nextHeight.isFinite ||
        nextWidth <= 0 ||
        nextHeight <= 0) {
      throw ArgumentError(
        'Rain surface dimensions must be finite and positive',
      );
    }
    final sx = nextWidth / width;
    final sy = nextHeight / height;
    for (final drop in drops) {
      drop.x *= sx;
      drop.y *= sy;
    }
    for (var i = 0; i < beads.length; i++) {
      final bead = beads[i];
      beads[i] = RainEffectBead(
        x: bead.x * sx,
        y: bead.y * sy,
        radius: bead.radius,
        seed: bead.seed,
      );
    }
    width = nextWidth;
    height = nextHeight;
  }

  /// Advances at most one 60 Hz reference frame. Zero/invalid time is inert.
  void step(double referenceFrames) {
    if (!referenceFrames.isFinite || referenceFrames <= 0) return;
    final dt = referenceFrames.clamp(0.0, 1.0);
    _spawnRain(dt);
    // The canvas upstream accumulates spray pixels; keep a bounded bead ring
    // instead, at a lower density suitable for legible application content.
    _beadAccumulator += .32 * dt * _areaMultiplier;
    while (_beadAccumulator >= 1) {
      _beadAccumulator--;
      addBead(
        RainEffectBead(
          x: random.nextDouble() * width,
          y: random.nextDouble() * height,
          radius: 1 + pow(random.nextDouble(), 2).toDouble() * 2,
          seed: random.nextDouble(),
        ),
      );
    }

    final trailBeads = <RainEffectBead>[];
    for (final drop in drops) {
      if (drop.killed) continue;
      if (random.nextDouble() <
          max(0, drop.radius - minRadius) *
              (.1 / (maxRadius - minRadius)) *
              dt) {
        drop.momentum += random.nextDouble() * (drop.radius / maxRadius) * 4;
      }
      if (drop.radius <= minRadius && random.nextDouble() < .05 * dt) {
        drop.shrink += .01;
      }
      drop.radius -= drop.shrink * dt;
      if (drop.radius <= .4 || !drop.isFinite) {
        drop.killed = true;
        continue;
      }

      drop.momentum = drop.momentum.clamp(0, 3.2);
      final distance = drop.momentum * dt * motionScale;
      drop.lastSpawn += distance;
      if (drop.lastSpawn > drop.nextSpawn && drop.momentum > .1) {
        trailBeads.add(
          RainEffectBead(
            x: drop.x + _between(-drop.radius, drop.radius) * .1,
            y: drop.y - drop.radius * .01,
            radius: (drop.radius * _between(.2, .5)).clamp(1.0, 4.6),
            seed: drop.seed,
          ),
        );
        // Retain upstream's trail shrinkage, scaled by distance so slow drops
        // do not evaporate merely because the display has a high refresh rate.
        drop.radius *= pow(.97, dt * motionScale).toDouble();
        drop.lastSpawn = 0;
        drop.nextSpawn = max(
          6,
          _between(minRadius, maxRadius) +
              maxRadius -
              drop.radius -
              drop.momentum * 2,
        );
      }

      drop.spreadX *= pow(.4, dt).toDouble();
      drop.spreadY *= pow(.7, dt).toDouble();
      // Upstream omitted dt here, causing movement to depend on frame rate.
      drop.y += distance;
      drop.x += drop.momentumX * dt * motionScale;
      drop.distanceTravelled += distance;
      if (drop.y > height + drop.radius ||
          drop.x < -drop.radius ||
          drop.x > width + drop.radius) {
        drop.killed = true;
        continue;
      }
      if (distance > 0) _clearBeads(drop);
    }

    _mergeDrops();
    for (final bead in trailBeads) {
      addBead(bead);
    }
    for (final drop in drops) {
      drop.momentum -=
          max(1, minRadius * .5 - drop.momentum) * .1 * dt * motionScale;
      drop.momentum = max(0, drop.momentum);
      drop.momentumX *= pow(.7, dt).toDouble();
    }
    drops.removeWhere((drop) => drop.killed);
  }

  void _spawnRain(double dt) {
    final limit = min(3, max(1, (3 * _areaMultiplier).ceil()));
    for (var count = 0; count < limit && drops.length < maxDrops; count++) {
      if (random.nextDouble() >=
          (.028 * spawnRate * dt * _areaMultiplier).clamp(0.0, .9)) {
        break;
      }
      addDrop(_newRainDrop());
    }
  }

  void _clearBeads(RainEffectDrop drop) {
    final radius = drop.radius * .43;
    beads.removeWhere((bead) {
      final dx = bead.x - drop.x;
      final dy = (bead.y - drop.y) / 1.5;
      return dx * dx + dy * dy < radius * radius;
    });
  }

  void _mergeDrops() {
    // Bounded by maxDrops; inspect each pair once, including larger drops
    // below smaller ones (the original sorted forward scan could miss these).
    for (var i = 0; i < drops.length; i++) {
      final a = drops[i];
      if (a.killed) continue;
      for (var j = i + 1; j < drops.length; j++) {
        final b = drops[j];
        if (b.killed) continue;
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final reach =
            (a.radius + b.radius) * (.65 + max(a.momentum, b.momentum) * .01);
        if (dx * dx + dy * dy >= reach * reach) continue;
        final survivor = a.radius >= b.radius ? a : b;
        final consumed = identical(survivor, a) ? b : a;
        // Original conserves 80% of the consumed projected area. Its maxR
        // check referenced an undefined field; clamp to the actual limit.
        final target = min(
          maxRadius,
          sqrt(
            survivor.radius * survivor.radius +
                consumed.radius * consumed.radius * .8,
          ),
        );
        survivor.momentumX += (consumed.x - survivor.x) * .1;
        survivor.radius = target;
        survivor.spreadX = 0;
        survivor.spreadY = 0;
        survivor.momentum = max(
          consumed.momentum,
          min(3.2, survivor.momentum + target * .05 + 1),
        );
        consumed.killed = true;
        if (a.killed) break;
      }
    }
  }
}

class RainEffectDrop {
  RainEffectDrop({
    required this.x,
    required this.y,
    required this.radius,
    this.momentum = 0,
    this.momentumX = 0,
    this.spreadX = 0,
    this.spreadY = 0,
    this.seed = .5,
  });

  double x, y, radius, momentum, momentumX, spreadX, spreadY, seed;
  double lastSpawn = 0, nextSpawn = 0, shrink = 0, distanceTravelled = 0;
  bool killed = false;
  bool get isFinite =>
      x.isFinite &&
      y.isFinite &&
      radius.isFinite &&
      momentum.isFinite &&
      momentumX.isFinite &&
      seed.isFinite &&
      spreadX.isFinite &&
      spreadY.isFinite;
}

class RainEffectBead {
  const RainEffectBead({
    required this.x,
    required this.y,
    required this.radius,
    required this.seed,
  });
  final double x, y, radius, seed;
}
