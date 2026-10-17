import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/effects/orion_rain_simulation.dart';
import 'package:orion/effects/rain_effect_physics.dart';

void main() {
  OrionRainSimulation pane([int seed = 7]) =>
      OrionRainSimulation(width: 1000, height: 700, random: Random(seed));

  test(
    'wet pane starts with dense visible beads and compact sliding drops',
    () {
      final simulation = pane();
      final rows = _rows(simulation.packet);
      final beads = rows.where((row) => row[5] == 0).toList();
      final drops = rows.where((row) => row[5] == 1).toList();
      expect(beads.length, inInclusiveRange(500, 900));
      expect(drops.length, inInclusiveRange(50, 120));
      expect(drops.every((row) => row[2] >= 3.5 && row[2] < 7), isTrue);
      expect(beads.every((row) => row[2] < 3.5 && row[3] < 4), isTrue);
      expect(beads.every((row) => row[4] >= .8 && row[4] <= 1), isTrue);
      expect(drops.every((row) => row[4] >= .7 && row[4] <= .85), isTrue);
      expect(
        drops.map((row) => (row[2] * 10).floor()).toSet().length,
        greaterThan(10),
      );
      expect(
        beads.map((row) => row[0].round()).toSet().length,
        greaterThan(400),
      );
      expect(rows.every((row) => row[6] >= 0 && row[6] < 1), isTrue);
      expect(rows.every((row) => row[7] >= 0 && row[7] <= 46), isTrue);
    },
  );

  test('identical seeds and fixed elapsed time give reproducible physics', () {
    final a = pane(12);
    final b = pane(12);
    for (var i = 0; i < 90; i++) {
      a.advance(const Duration(microseconds: 33334));
      b.advance(const Duration(microseconds: 16667));
      b.advance(const Duration(microseconds: 16667));
    }
    expect(a.packet, orderedEquals(b.packet));
  });

  test('30Hz and 60Hz tick partitioning preserves timing remainder', () {
    final a = pane();
    final b = pane();
    for (var i = 0; i < 120; i++) {
      a.advance(const Duration(microseconds: 25000));
      b.advance(const Duration(microseconds: 10000));
      b.advance(const Duration(microseconds: 15000));
    }
    expect(a.packet, orderedEquals(b.packet));
  });

  test('zero, negative and sub-step deltas preserve the same packet', () {
    final simulation = pane();
    final before = simulation.packet;
    simulation.advance(Duration.zero);
    simulation.advance(const Duration(days: -1));
    simulation.advance(const Duration(microseconds: 1));
    expect(identical(simulation.packet, before), isTrue);
  });

  test('resume after a long stall has a bounded eight-step catchup', () {
    final stalled = pane();
    final bounded = pane();
    stalled.advance(const Duration(days: 10));
    bounded.advance(const Duration(microseconds: 16667 * 8));
    expect(stalled.packet, orderedEquals(bounded.packet));
  });

  test(
    'small sliding drops visibly move down while seed identity persists',
    () {
      final simulation = pane();
      final before = {
        for (final row in _rows(simulation.packet).where((row) => row[5] == 1))
          row[6]: row[1],
      };
      simulation.advance(const Duration(microseconds: 16667 * 8));
      final moved = _rows(simulation.packet).where(
        (row) =>
            row[5] == 1 &&
            before.containsKey(row[6]) &&
            row[1] > before[row[6]]!,
      );
      expect(moved.length, greaterThan(8));
    },
  );

  test(
    'compact rain profile travels faster than the previous large-drop profile',
    () {
      final currentProfile = pane().physics;
      final current = RainEffectPhysics(
        width: 1000,
        height: 700,
        random: Random(52),
        maxDrops: 1,
        minRadius: currentProfile.minRadius,
        maxRadius: currentProfile.maxRadius,
        motionScale: currentProfile.motionScale,
      );
      final previous = RainEffectPhysics(
        width: 1000,
        height: 700,
        random: Random(52),
        maxDrops: 1,
        minRadius: 8,
        maxRadius: 15,
        motionScale: .2,
      );
      // Identical starting state and random stream isolate the profile's motion.
      // A full collection and disabled daughter spawning prevent unrelated new
      // drops or coalescence from inflating this measured downward displacement.
      for (final physics in [current, previous]) {
        physics.addDrop(
          RainEffectDrop(x: 500, y: 100, radius: 3.5, momentum: 2.5)
            ..nextSpawn = double.infinity,
        );
        for (var frame = 0; frame < 30; frame++) {
          physics.step(1);
        }
      }
      final currentTravel = current.drops.single.y - 100;
      final previousTravel = previous.drops.single.y - 100;
      expect(currentTravel, greaterThan(previousTravel * 2));
      expect(currentTravel, greaterThan(20));
      expect(current.drops.single.radius, lessThanOrEqualTo(current.maxRadius));
    },
  );

  test('resize preserves proportional locations and logical lens sizes', () {
    final simulation = pane();
    final before = Float32List.fromList(simulation.packet);
    simulation.resize(width: 500, height: 1050);
    expect(simulation.width, 500);
    expect(simulation.height, 1050);
    final after = simulation.packet;
    expect(after.length, before.length);
    for (var i = 0; i < after.length; i += 8) {
      expect(after[i], closeTo(before[i] * .5, .001));
      expect(after[i + 1], closeTo(before[i + 1] * 1.5, .001));
      expect(
        after.sublist(i + 2, i + 8),
        orderedEquals(before.sublist(i + 2, i + 8)),
      );
    }
  });

  test('invalid surface dimensions are rejected without poisoning state', () {
    for (final width in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => OrionRainSimulation(width: width, height: 700),
        throwsArgumentError,
      );
    }
    final simulation = pane();
    final before = simulation.packet;
    expect(() => simulation.resize(width: 0, height: 10), throwsArgumentError);
    expect(simulation.width, 1000);
    expect(identical(simulation.packet, before), isTrue);
  });

  test(
    'normal and compact panes have dense wet coverage from small lenses',
    () {
      for (final size in [(1000.0, 700.0), (822.0, 523.0)]) {
        final simulation = OrionRainSimulation(
          width: size.$1,
          height: size.$2,
          random: Random(31),
        );
        final rows = _rows(simulation.packet);
        final area = size.$1 * size.$2;
        expect(
          rows.where((row) => row[5] == 0).length,
          greaterThan(area * .0007),
        );
        expect(
          rows.where((row) => row[5] == 1).length,
          greaterThan(area * .00007),
        );
        // Estimate the union of actual elliptical lens bodies, excluding tails.
        // This catches an apparently populated pane whose beads were shrunk to
        // invisible specks; increasing blur/warp alone cannot satisfy coverage.
        expect(
          _lensCoverage(simulation.packet, width: size.$1, height: size.$2),
          greaterThan(.012),
        );
        expect(simulation.dropCount, lessThanOrEqualTo(2048));
      }
    },
  );

  test('long-running storm remains finite and below native packet budget', () {
    final simulation = OrionRainSimulation(
      width: 822,
      height: 523,
      random: Random(98),
    );
    final sustainedMovingCounts = <int>[];
    for (var i = 0; i < 600; i++) {
      simulation.advance(const Duration(milliseconds: 100));
      expect(simulation.packet.length % 8, 0);
      expect(simulation.dropCount, lessThanOrEqualTo(1020));
      expect(simulation.packet.every((value) => value.isFinite), isTrue);
      expect(simulation.physics.drops.length, lessThanOrEqualTo(120));
      expect(simulation.physics.beads.length, lessThanOrEqualTo(900));
      expect(
        simulation.physics.drops.every((drop) => drop.radius <= 6.5),
        isTrue,
      );
      if (i % 100 == 99) {
        sustainedMovingCounts.add(simulation.physics.drops.length);
      }
    }
    expect(simulation.physics.beads.length, greaterThan(300));
    expect(
      sustainedMovingCounts,
      everyElement(greaterThanOrEqualTo(30)),
      reason:
          'Rain must replenish sliding drops instead of fading to a handful',
    );
  });

  test('core merges overlapping lenses from either size ordering', () {
    for (final reverse in [false, true]) {
      final physics = RainEffectPhysics(
        width: 1000,
        height: 700,
        random: _HighRandom(),
      );
      final small = RainEffectDrop(x: 100, y: 100, radius: 6);
      final large = RainEffectDrop(x: 102, y: 100, radius: 8);
      physics.addDrop(reverse ? large : small);
      physics.addDrop(reverse ? small : large);
      physics.step(1);
      expect(physics.drops, hasLength(1));
      expect(identical(physics.drops.single, large), isTrue);
      expect(large.radius, closeTo(sqrt(8 * 8 + 6 * 6 * .8), .000001));
      expect(large.momentum, greaterThan(0));
    }
  });

  test('coalescing lenses clamp to maximum radius and never self-collide', () {
    final physics = RainEffectPhysics(
      width: 1000,
      height: 700,
      random: _HighRandom(),
    );
    final a = RainEffectDrop(x: 100, y: 100, radius: 15);
    physics.addDrop(a);
    physics.step(1);
    expect(a.radius, 15);
    physics.addDrop(RainEffectDrop(x: 100, y: 100, radius: 14));
    physics.step(1);
    expect(physics.drops, hasLength(1));
    expect(physics.drops.single.radius, 15);
  });

  test('moving drops sweep old spray while retaining daughter trail beads', () {
    final physics = RainEffectPhysics(
      width: 1000,
      height: 700,
      random: _HighRandom(),
    );
    const old = RainEffectBead(x: 100, y: 100, radius: 2, seed: .1);
    physics.addBead(old);
    physics.addDrop(RainEffectDrop(x: 100, y: 100, radius: 12, momentum: 2));
    physics.step(1);
    expect(physics.beads.contains(old), isFalse);
    expect(physics.beads, isNotEmpty);
    expect(
      physics.beads.any((bead) => bead.y < physics.drops.single.y),
      isTrue,
    );
  });

  test('rain drops leave pane and collection limits reject excess inputs', () {
    final physics = RainEffectPhysics(
      width: 100,
      height: 100,
      random: _HighRandom(),
      maxDrops: 2,
      maxBeads: 2,
    );
    physics.addDrop(RainEffectDrop(x: 50, y: 120, radius: 9, momentum: 2));
    physics.addDrop(RainEffectDrop(x: 20, y: 20, radius: 9));
    expect(physics.addDrop(RainEffectDrop(x: 80, y: 20, radius: 9)), isFalse);
    physics.step(1);
    expect(physics.drops, hasLength(1));
    for (var i = 0; i < 5; i++) {
      physics.addBead(
        RainEffectBead(x: i.toDouble(), y: 0, radius: 1, seed: .5),
      );
    }
    expect(physics.beads, hasLength(2));
    expect(
      physics.addDrop(RainEffectDrop(x: double.nan, y: 0, radius: 9)),
      isFalse,
    );
  });
}

List<List<double>> _rows(Float32List packet) => [
  for (var i = 0; i < packet.length; i += 8) packet.sublist(i, i + 8),
];

double _lensCoverage(
  Float32List packet, {
  required double width,
  required double height,
}) {
  const spacing = 2.0;
  final columns = (width / spacing).ceil();
  final rows = (height / spacing).ceil();
  final wet = Uint8List(columns * rows);
  var wetSamples = 0;
  for (var i = 0; i < packet.length; i += 8) {
    final x = packet[i], y = packet[i + 1];
    final rx = packet[i + 2], ry = packet[i + 3];
    final left = max(0, ((x - rx) / spacing).floor());
    final right = min(columns - 1, ((x + rx) / spacing).floor());
    final top = max(0, ((y - ry) / spacing).floor());
    final bottom = min(rows - 1, ((y + ry) / spacing).floor());
    for (var cy = top; cy <= bottom; cy++) {
      for (var cx = left; cx <= right; cx++) {
        final dx = ((cx + .5) * spacing - x) / rx;
        final dy = ((cy + .5) * spacing - y) / ry;
        final index = cy * columns + cx;
        if (dx * dx + dy * dy <= 1 && wet[index] == 0) {
          wet[index] = 1;
          wetSamples++;
        }
      }
    }
  }
  return wetSamples / wet.length;
}

class _HighRandom implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => .999;
  @override
  int nextInt(int max) => max - 1;
}
