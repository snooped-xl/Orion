import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// Native desktop sampling is optional; the authored Flutter scene remains the
/// fallback whenever the compositor or its extension is unavailable.
class NativeDesktopGlassViewport extends StatefulWidget {
  const NativeDesktopGlassViewport({
    super.key,
    required this.supported,
    required this.enabled,
    this.opacity = 1,
    this.cornerRadius = 16,
    required this.builder,
    this.onActiveChanged,
  });

  final bool supported, enabled;
  final double opacity, cornerRadius;
  final Widget Function(BuildContext context, bool active) builder;
  final FutureOr<void> Function(bool active)? onActiveChanged;

  @override
  State<NativeDesktopGlassViewport> createState() =>
      _NativeDesktopGlassViewportState();
}

class NativeDesktopGlassScope extends InheritedWidget {
  const NativeDesktopGlassScope({
    super.key,
    required this.active,
    required this.opacity,
    required super.child,
  });

  final bool active;
  final double opacity;

  static bool isActiveOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NativeDesktopGlassScope>()
          ?.active ??
      false;

  static double opacityOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NativeDesktopGlassScope>()
          ?.opacity ??
      1;

  @override
  bool updateShouldNotify(NativeDesktopGlassScope oldWidget) =>
      active != oldWidget.active || opacity != oldWidget.opacity;
}

class _GlassConfiguration {
  const _GlassConfiguration(this.enabled, this.radius, this.revision);
  final bool enabled;
  final double radius;
  final int revision;

  bool matches(_GlassConfiguration other) =>
      enabled == other.enabled &&
      radius == other.radius &&
      revision == other.revision;
}

class _NativeDesktopGlassViewportState
    extends State<NativeDesktopGlassViewport> {
  static const _channel = MethodChannel('orion/window');
  static const _pollInterval = Duration(seconds: 5);
  static const _requestTimeout = Duration(seconds: 3);
  static const _mapRetryDelays = [
    Duration(milliseconds: 250),
    Duration(milliseconds: 750),
    Duration(milliseconds: 1500),
  ];
  final _foreground = GlobalKey();
  Timer? _poll;
  Timer? _mapRetry;
  int _mapRetryAttempt = 0;
  int _revision = 0, _callbackRevision = 0;
  bool _active = false, _disposed = false, _draining = false;
  bool _desiredEnabled = false;
  _GlassConfiguration? _queued, _inFlight;
  Future<void> _callbacks = Future.value();

  double get _radius => widget.cornerRadius.isFinite
      ? widget.cornerRadius.clamp(0, 256).toDouble()
      : 16;
  double get _opacity =>
      widget.opacity.isFinite ? widget.opacity.clamp(.5, 1).toDouble() : 1;

  @override
  void initState() {
    super.initState();
    _synchronize();
  }

  @override
  void didUpdateWidget(covariant NativeDesktopGlassViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.supported != widget.supported ||
        (widget.supported &&
            widget.enabled &&
            oldWidget.cornerRadius != widget.cornerRadius) ||
        (widget.enabled && oldWidget.opacity != widget.opacity)) {
      _synchronize();
    }
  }

  void _synchronize() {
    _revision++;
    _poll?.cancel();
    _poll = null;
    _resetMapRetries();
    final previouslyEnabled = _desiredEnabled;
    _desiredEnabled = widget.supported && widget.enabled;
    if (!_desiredEnabled) _setActive(false);
    if (widget.supported || previouslyEnabled) {
      _enqueue(_GlassConfiguration(_desiredEnabled, _radius, _revision));
    }
    if (_desiredEnabled) {
      _poll = Timer.periodic(_pollInterval, (_) {
        if (!_disposed && _desiredEnabled) {
          _enqueue(_GlassConfiguration(true, _radius, _revision));
        }
      });
    }
  }

  void _enqueue(_GlassConfiguration configuration) {
    if (_inFlight?.matches(configuration) == true) return;
    _queued = configuration;
    if (!_draining) unawaited(_drain());
  }

  Future<void> _drain() async {
    _draining = true;
    while (_queued != null) {
      final configuration = _queued!;
      _queued = null;
      if (configuration.enabled &&
          (_disposed || configuration.revision != _revision)) {
        continue;
      }
      _inFlight = configuration;
      var active = false;
      String? reason;
      try {
        final response = await _channel
            .invokeMethod<Object?>('configureDesktopGlass', {
              'enabled': configuration.enabled,
              'cornerRadius': configuration.radius,
              'opacity': _opacity,
            })
            .timeout(_requestTimeout);
        final decoded = response is String ? jsonDecode(response) : response;
        if (decoded is Map && decoded['reason'] is String) {
          reason = decoded['reason'] as String;
        }
        active =
            configuration.enabled &&
            decoded is Map &&
            decoded['ok'] == true &&
            decoded['active'] == true;
      } catch (_) {
        // Missing plugins, extension loss and malformed replies all retain the
        // ordinary Flutter backdrop. The next enabled poll can recover.
      }
      _inFlight = null;
      if (!_disposed && configuration.revision == _revision) {
        _setActive(active && _desiredEnabled);            if (_desiredEnabled &&
                !active &&
                (reason == 'waiting-window' || reason == 'unavailable')) {
          _retryWhenMapped();
        } else {
          _resetMapRetries();
        }
      }
    }
    _draining = false;
  }

  void _resetMapRetries() {
    _mapRetry?.cancel();
    _mapRetry = null;
    _mapRetryAttempt = 0;
  }

  void _retryWhenMapped() {
    if (_mapRetryAttempt >= _mapRetryDelays.length) return;
    _mapRetry?.cancel();
    final revision = _revision;
    _mapRetry = Timer(_mapRetryDelays[_mapRetryAttempt++], () {
      _mapRetry = null;
      if (!_disposed && _desiredEnabled && revision == _revision) {
        _enqueue(_GlassConfiguration(true, _radius, revision));
      }
    });
  }

  void _setActive(bool active) {
    if (_disposed || active == _active) return;
    _active = active;
    if (mounted) setState(() {});
    final callback = widget.onActiveChanged;
    final revision = ++_callbackRevision;
    if (callback == null) return;
    _callbacks = _callbacks.then((_) async {
      if (_disposed || revision != _callbackRevision) return;
      try {
        await callback(active);
      } catch (_) {
        // Window opacity restoration may race native window teardown. Keep
        // these best-effort host callbacks ordered without leaking errors.
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _callbackRevision++;
    _poll?.cancel();
    _mapRetry?.cancel();
    if (_desiredEnabled) {
      // Serialize cleanup after any activation already in flight. Its late
      // response cannot rebuild the disposed foreground or re-enable polling.
      _queued = _GlassConfiguration(false, _radius, _revision);
      if (!_draining) unawaited(_drain());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NativeDesktopGlassScope(
    active: _active,
    opacity: _opacity,
    child: KeyedSubtree(
      key: _foreground,
      child: Builder(builder: (context) => widget.builder(context, _active)),
    ),
  );
}
