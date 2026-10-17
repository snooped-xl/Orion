import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/window_morph_service.dart';

void main() {
  const normal = Rect.fromLTWH(100, 100, 822, 523);
  final compact = Rect.fromCenter(
    center: normal.center,
    width: 740,
    height: 470,
  );

  testWidgets('spatial morph keeps its center and lands on exact bounds', (
    tester,
  ) async {
    final native = _BoundsAdapter(normal);
    final morph = WindowMorphService(vsync: const TestVSync(), adapter: native);
    addTearDown(morph.dispose);

    final completed = morph.animateTo(compact);
    expect(morph.isAnimating, isTrue);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(native.writes.length, greaterThan(1));
    expect(native.bounds.width, lessThan(normal.width));
    expect(native.bounds, isNot(compact));
    for (final frame in native.writes) {
      expect(frame.center.dx, closeTo(normal.center.dx, .00001));
      expect(frame.center.dy, closeTo(normal.center.dy, .00001));
    }
    await tester.pump(const Duration(milliseconds: 360));
    expect(await completed, isTrue);
    expect(native.bounds, compact);
    expect(morph.isAnimating, isFalse);
    expect(native.maximumConcurrentWrites, 1);

    // The caller can restore an arbitrary original user-sized rectangle.
    const restored = Rect.fromLTWH(52, 73, 1044, 692);
    final reverse = morph.animateTo(restored);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 480));
    expect(await reverse, isTrue);
    expect(native.bounds, restored);
  });

  testWidgets(
    'slow native writes coalesce frames instead of queuing a backlog',
    (tester) async {
      final native = _BoundsAdapter(normal, holdWrites: true);
      final morph = WindowMorphService(
        vsync: const TestVSync(),
        adapter: native,
      );
      addTearDown(morph.dispose);
      final completed = morph.animateTo(compact);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));
      expect(native.writes, hasLength(1));

      native.releaseWrite();
      await tester.pump();
      expect(native.writes, hasLength(2));
      expect(native.writes.last, compact);
      native.releaseWrite();
      await tester.pump();
      expect(await completed, isTrue);
      expect(native.maximumConcurrentWrites, 1);
    },
  );

  testWidgets(
    'rapid retarget waits for native bounds and the newest request wins',
    (tester) async {
      final native = _BoundsAdapter(normal, holdWrites: true);
      final morph = WindowMorphService(
        vsync: const TestVSync(),
        adapter: native,
      );
      addTearDown(morph.dispose);
      final first = morph.animateTo(compact);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final second = morph.animateTo(const Rect.fromLTWH(60, 80, 800, 500));
      final third = morph.animateTo(normal);
      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(native.writes, hasLength(1));
      expect(native.reads, 1);

      native.releaseWrite();
      await tester.pump();
      // The first in-flight frame was the original rectangle, so no redundant
      // reverse writes are necessary once that actual position is confirmed.
      expect(await third, isTrue);
      expect(native.writes, hasLength(1));
      expect(native.reads, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(native.writes, hasLength(1));
      expect(native.bounds, normal);
    },
  );

  testWidgets('cancel waits for the active write and discards pending frames', (
    tester,
  ) async {
    final native = _BoundsAdapter(normal, holdWrites: true);
    final morph = WindowMorphService(vsync: const TestVSync(), adapter: native);
    addTearDown(morph.dispose);
    final completed = morph.animateTo(compact);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    var idle = false;
    final cancel = morph.cancel().then((_) => idle = true);
    expect(await completed, isFalse);
    expect(idle, isFalse);
    native.releaseWrite();
    await tester.pump();
    await cancel;
    expect(idle, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(native.writes, hasLength(1));
    expect(morph.isAnimating, isFalse);
  });

  testWidgets(
    'reduced motion and zero duration each apply one immediate write',
    (tester) async {
      final native = _BoundsAdapter(normal);
      final morph = WindowMorphService(
        vsync: const TestVSync(),
        adapter: native,
      );
      addTearDown(morph.dispose);
      final reduced = morph.animateTo(compact, reducedMotion: true);
      await tester.pump();
      expect(await reduced, isTrue);
      expect(native.writes, [compact]);
      expect(native.reads, 0);
      final instant = morph.animateTo(normal, duration: Duration.zero);
      await tester.pump();
      expect(await instant, isTrue);
      expect(native.writes, [compact, normal]);
      await tester.pump(const Duration(seconds: 1));
      expect(native.writes, hasLength(2));
    },
  );

  testWidgets('disposal cannot leave later native frames behind', (
    tester,
  ) async {
    final native = _BoundsAdapter(normal, holdWrites: true);
    final morph = WindowMorphService(vsync: const TestVSync(), adapter: native);
    final completed = morph.animateTo(compact);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    morph.dispose();
    expect(await completed, isFalse);
    native.releaseWrite();
    await morph.cancel();
    await tester.pump(const Duration(seconds: 1));
    expect(native.writes, hasLength(1));
    expect(() => morph.animateTo(normal), throwsStateError);
    await expectLater(morph.getBounds(), throwsStateError);
    morph.dispose();
  });

  testWidgets('a native failure is reported and does not poison later morphs', (
    tester,
  ) async {
    final native = _BoundsAdapter(normal)..nextFailure = StateError('native');
    final morph = WindowMorphService(vsync: const TestVSync(), adapter: native);
    addTearDown(morph.dispose);
    final failed = morph.animateTo(compact, reducedMotion: true);
    final expectation = expectLater(failed, throwsStateError);
    await tester.pump();
    await expectation;
    expect(morph.isAnimating, isFalse);
    final retry = morph.animateTo(compact, reducedMotion: true);
    await tester.pump();
    expect(await retry, isTrue);
    expect(await morph.getBounds(), compact);
  });

  testWidgets(
    'a supplied settled start avoids a redundant native bounds read',
    (tester) async {
      final native = _BoundsAdapter(normal);
      final morph = WindowMorphService(
        vsync: const TestVSync(),
        adapter: native,
      );
      addTearDown(morph.dispose);
      final completed = morph.animateTo(compact, start: normal);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 480));
      expect(await completed, isTrue);
      expect(native.reads, 0);
      expect(native.bounds, compact);
      expect(native.maximumConcurrentWrites, 1);
    },
  );

  testWidgets(
    'a supplied start is ignored while an old native write is active',
    (tester) async {
      final native = _BoundsAdapter(normal, holdWrites: true);
      final morph = WindowMorphService(
        vsync: const TestVSync(),
        adapter: native,
      );
      addTearDown(morph.dispose);
      final first = morph.animateTo(compact);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final next = morph.animateTo(normal, start: compact);
      expect(await first, isFalse);
      native.releaseWrite();
      await tester.pump();
      expect(await next, isTrue);
      expect(native.reads, 2);
      expect(native.writes, hasLength(1));
      expect(native.bounds, normal);
    },
  );

  testWidgets('invalid sizes fail before any native call', (tester) async {
    final native = _BoundsAdapter(normal);
    final morph = WindowMorphService(vsync: const TestVSync(), adapter: native);
    addTearDown(morph.dispose);
    for (final invalid in [
      const Rect.fromLTWH(0, 0, 0, 100),
      const Rect.fromLTWH(0, 0, 100, -1),
      const Rect.fromLTWH(double.nan, 0, 100, 100),
      const Rect.fromLTWH(0, 0, double.infinity, 100),
      const Rect.fromLTWH(0, 0, 16385, 100),
    ]) {
      expect(() => morph.animateTo(invalid), throwsArgumentError);
    }
    expect(
      () =>
          morph.animateTo(compact, duration: const Duration(milliseconds: -1)),
      throwsArgumentError,
    );
    expect(native.reads, 0);
    expect(native.writes, isEmpty);
  });
}

class _BoundsAdapter implements WindowBoundsAdapter {
  _BoundsAdapter(this.bounds, {this.holdWrites = false});

  Rect bounds;
  final bool holdWrites;
  final writes = <Rect>[];
  final _held = <Completer<void>>[];
  int reads = 0;
  int _activeWrites = 0;
  int maximumConcurrentWrites = 0;
  Object? nextFailure;

  @override
  Future<Rect> getBounds() async {
    reads++;
    return bounds;
  }

  @override
  Future<void> setBounds(Rect next) async {
    writes.add(next);
    _activeWrites++;
    if (_activeWrites > maximumConcurrentWrites) {
      maximumConcurrentWrites = _activeWrites;
    }
    try {
      if (holdWrites) {
        final held = Completer<void>();
        _held.add(held);
        await held.future;
      }
      final failure = nextFailure;
      nextFailure = null;
      if (failure != null) throw failure;
      bounds = next;
    } finally {
      _activeWrites--;
    }
  }

  void releaseWrite() => _held.removeAt(0).complete();
}
