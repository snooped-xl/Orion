import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/expressive_motion.dart';

/// The native boundary is injectable so resize races can be tested without GTK.
abstract interface class WindowBoundsAdapter {
  Future<Rect> getBounds();
  Future<void> setBounds(Rect bounds);
}

class WindowManagerBoundsAdapter implements WindowBoundsAdapter {
  const WindowManagerBoundsAdapter();

  @override
  Future<Rect> getBounds() => windowManager.getBounds();

  @override
  Future<void> setBounds(Rect bounds) =>
      windowManager.setBounds(bounds, animate: false);
}

/// Morphs the window without rebuilding the editor or changing its focus.
///
/// Native calls are serialized. When GTK is slower than the display, only the
/// newest animation frame waits behind the active call. Retargeting starts at
/// the actual native bounds after that active call has settled.
class WindowMorphService {
  WindowMorphService({
    required TickerProvider vsync,
    WindowBoundsAdapter? adapter,
  }) : _adapter = adapter ?? const WindowManagerBoundsAdapter(),
       _animation = AnimationController(vsync: vsync) {
    _animation.addListener(_tick);
    _animation.addStatusListener(_statusChanged);
  }

  static const defaultDuration = Duration(milliseconds: 480);

  final WindowBoundsAdapter _adapter;
  final AnimationController _animation;
  _MorphRequest? _request;
  _BoundsFrame? _pending;
  Completer<void>? _drainCompletion;
  bool _disposed = false;

  bool get isAnimating => _request != null;

  /// Reads settled native bounds, including any resize already in flight.
  Future<Rect> getBounds() async {
    _checkAlive();
    await _waitForNative();
    _checkAlive();
    return _adapter.getBounds();
  }

  /// Returns true only when [target] has reached the native window.
  ///
  /// A newer request, [cancel], or [dispose] resolves the old request as false.
  /// Reduced motion and a zero duration apply one immediate native update.
  /// [start] may reuse bounds the caller has just read from the settled window;
  /// an existing native write invalidates it and forces a fresh read instead.
  Future<bool> animateTo(
    Rect target, {
    Duration duration = defaultDuration,
    bool reducedMotion = false,
    Rect? start,
  }) {
    _checkAlive();
    _validateBounds(target);
    if (start != null) _validateBounds(start);
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'Must not be negative.');
    }
    _cancelCurrent();
    // A caller which just read settled native bounds can supply them instead
    // of repeating the same platform round trip before the first frame. Never
    // trust them across a native resize still in flight.
    final settledStart = _drainCompletion == null ? start : null;
    final request = _MorphRequest(
      target,
      duration,
      reducedMotion,
      settledStart,
    );
    _request = request;
    unawaited(_prepare(request));
    return request.completion.future;
  }

  /// Drops pending frames and waits for an already dispatched call to finish.
  ///
  /// Await this before another owner changes the window's shell or profile.
  /// The method can also be called after [dispose].
  Future<void> cancel() {
    _cancelCurrent();
    return _waitForNative();
  }

  void dispose() {
    if (_disposed) return;
    _cancelCurrent();
    _disposed = true;
    _animation.dispose();
  }

  Future<void> _prepare(_MorphRequest request) async {
    try {
      await _waitForNative();
      if (!_isCurrent(request)) return;
      if (request.reducedMotion || request.duration == Duration.zero) {
        _queue(_BoundsFrame(request, request.target, isFinal: true));
        return;
      }
      final start = request.start ?? await _adapter.getBounds();
      if (!_isCurrent(request)) return;
      if (start == request.target) {
        _finish(request, true);
        return;
      }
      _validateBounds(start);
      request.start = start;
      _animation.duration = request.duration;
      _animation.forward(from: 0);
    } catch (error, stack) {
      _fail(request, error, stack);
    }
  }

  void _tick() {
    final request = _request;
    if (request == null || request.start == null || _disposed) return;
    final progress = _animation.value;
    final bounds = progress == 1
        ? request.target
        : Rect.lerp(
            request.start,
            request.target,
            OrionMotion.spatial.transform(progress),
          )!;
    _queue(_BoundsFrame(request, bounds, isFinal: progress == 1));
  }

  void _statusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final request = _request;
    if (request == null || _disposed) return;
    // Always land on the exact requested rectangle, after any spring overshoot.
    _queue(_BoundsFrame(request, request.target, isFinal: true));
  }

  void _queue(_BoundsFrame frame) {
    if (!_isCurrent(frame.request)) return;
    _pending = frame;
    if (_drainCompletion != null) return;
    final completion = Completer<void>();
    _drainCompletion = completion;
    unawaited(_drain(completion));
  }

  Future<void> _drain(Completer<void> completion) async {
    try {
      while (_pending != null && !_disposed) {
        final frame = _pending!;
        _pending = null;
        if (!_isCurrent(frame.request)) continue;
        try {
          await _adapter.setBounds(frame.bounds);
          if (frame.isFinal && _isCurrent(frame.request)) {
            _finish(frame.request, true);
          }
        } catch (error, stack) {
          _fail(frame.request, error, stack);
        }
      }
    } finally {
      _drainCompletion = null;
      completion.complete();
    }
  }

  Future<void> _waitForNative() async {
    // Retargeting clears the pending slot. Only the active call must settle.
    final completion = _drainCompletion;
    if (completion != null) await completion.future;
  }

  bool _isCurrent(_MorphRequest request) =>
      !_disposed && identical(_request, request);

  void _cancelCurrent() {
    if (!_disposed) _animation.stop();
    _pending = null;
    final previous = _request;
    _request = null;
    if (previous != null && !previous.completion.isCompleted) {
      previous.completion.complete(false);
    }
  }

  void _finish(_MorphRequest request, bool completed) {
    if (!_isCurrent(request)) return;
    _animation.stop();
    _pending = null;
    _request = null;
    request.completion.complete(completed);
  }

  void _fail(_MorphRequest request, Object error, StackTrace stack) {
    if (!_isCurrent(request)) return;
    _animation.stop();
    _pending = null;
    _request = null;
    request.completion.completeError(error, stack);
  }

  void _checkAlive() {
    if (_disposed) throw StateError('WindowMorphService has been disposed.');
  }

  static void _validateBounds(Rect bounds) {
    if (!bounds.left.isFinite ||
        !bounds.top.isFinite ||
        !bounds.width.isFinite ||
        !bounds.height.isFinite ||
        bounds.width <= 0 ||
        bounds.height <= 0 ||
        bounds.width > 16384 ||
        bounds.height > 16384) {
      throw ArgumentError.value(
        bounds,
        'bounds',
        'Invalid native window bounds.',
      );
    }
  }
}

class _MorphRequest {
  _MorphRequest(this.target, this.duration, this.reducedMotion, this.start);

  final Rect target;
  final Duration duration;
  final bool reducedMotion;
  final completion = Completer<bool>();
  Rect? start;
}

class _BoundsFrame {
  const _BoundsFrame(this.request, this.bounds, {required this.isFinal});

  final _MorphRequest request;
  final Rect bounds;
  final bool isFinal;
}
