import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../services/monaco_editor_service.dart';
import '../effects/orion_rain_simulation.dart';

/// Supplies a private, bounded texture to the input-transparent GTK rain layer.
/// The boundary contains the Navigator, so lenses also refract open dialogs.
/// Native WebKit is captured separately because it paints above Flutter.
class NativeRainViewport extends StatefulWidget {
  const NativeRainViewport({
    super.key,
    required this.supported,
    required this.rainEnabled,
    required this.windowOpacity,
    required this.reducedMotion,
    required this.cornerRadius,
    required this.child,
    this.editorService,
  });

  final bool supported;
  final bool rainEnabled;
  final double windowOpacity;
  final bool reducedMotion;
  final double cornerRadius;
  final MonacoEditorService? editorService;
  final Widget child;

  @override
  State<NativeRainViewport> createState() => _NativeRainViewportState();
}

class _NativeRainViewportState extends State<NativeRainViewport>
    with WindowListener, WidgetsBindingObserver {
  static const _channel = MethodChannel('orion/rain');
  final _boundary = GlobalKey();
  Timer? _timer;
  Timer? _configurationRetry;
  Timer? _physicsTimer;
  OrionRainSimulation? _simulation;
  Size _simulationSize = Size.zero;
  Duration? _lastPhysicsFrame;
  bool _sendingDrops = false;
  bool _capturing = false;
  bool _minimized = false;
  bool _maximized = false;
  bool _unavailable = false;
  bool _channelUnavailable = false;
  bool _nativeConfigured = false;
  Uint8List? _flutterPng;
  _RainCaptureLayer? _capturedLayer;
  int _capturedLayerRevision = -1;
  Size? _capturedSize;
  int _revision = 0;
  int _windowShapeRevision = 0;

  bool get _active =>
      widget.supported && !_minimized && !_unavailable && widget.rainEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.supported) windowManager.addListener(this);
    _configure();
    if (widget.supported) unawaited(_readWindowShape());
  }

  @override
  void didUpdateWidget(covariant NativeRainViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.supported != widget.supported) {
      if (widget.supported) {
        windowManager.addListener(this);
        unawaited(_readWindowShape());
      } else {
        windowManager.removeListener(this);
        _resetNative();
      }
    }
    if (oldWidget.rainEnabled != widget.rainEnabled ||
        oldWidget.windowOpacity != widget.windowOpacity ||
        oldWidget.reducedMotion != widget.reducedMotion ||
        oldWidget.cornerRadius != widget.cornerRadius ||
        oldWidget.supported != widget.supported) {
      _configure();
    }
  }

  void _configure() {
    final revision = ++_revision;
    _timer?.cancel();
    _configurationRetry?.cancel();
    _timer = null;
    _physicsTimer?.cancel();
    _physicsTimer = null;
    _lastPhysicsFrame = null;
    if (!widget.rainEnabled) {
      _simulation = null;
      _simulationSize = Size.zero;
      _flutterPng = null;
      _capturedLayer = null;
      _capturedSize = null;
    }
    if (!widget.supported || _channelUnavailable) return;
    unawaited(_sendConfiguration(revision));
  }

  Future<void> _sendConfiguration(int revision, [int attempt = 0]) async {
    if (!mounted || revision != _revision || !widget.supported) return;
    try {
      _nativeConfigured = true;
      await _channel.invokeMethod<void>('configure', {
        'enabled': _active,
        'reducedMotion': widget.reducedMotion,
        'opacity': widget.windowOpacity.clamp(.5, 1),
        'cornerRadius': _maximized ? 0.0 : widget.cornerRadius,
      });
      if (!mounted || revision != _revision || !_active) return;
      // Flutter drives the droplet simulation. The GPU samples live widget and
      // WebKit textures only in wet regions; dry content stays fully live.
      if (!widget.reducedMotion) {
        // The native compositor renders on packet updates. A Dart timer avoids
        // producing 60 unnecessary Flutter scene frames per second for it.
        _physicsTimer = Timer.periodic(
          const Duration(microseconds: 33333),
          (timer) => _animateRain(Duration(microseconds: timer.tick * 33333)),
        );
      }
      _timer = Timer.periodic(
        Duration(milliseconds: widget.reducedMotion ? 400 : 100),
        (_) => unawaited(_capture()),
      );
      unawaited(_capture());
    } on MissingPluginException {
      _stopUnavailableEffect(missingPlugin: true);
    } on PlatformException catch (error) {
      if (error.code == 'rain_shader_unavailable') {
        _stopUnavailableEffect();
        return;
      }
      // A newly mapped GL surface may not be ready on the first frame.
      if (mounted && revision == _revision && attempt < 2) {
        _configurationRetry = Timer(
          Duration(milliseconds: 250 * (attempt + 1)),
          () => unawaited(_sendConfiguration(revision, attempt + 1)),
        );
      }
    }
  }

  bool _ensureSimulation() {
    final renderObject = _boundary.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary || !renderObject.hasSize) {
      return false;
    }
    final size = renderObject.size;
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) {
      return false;
    }
    if (_simulation == null) {
      _simulationSize = size;
      _simulation = OrionRainSimulation(width: size.width, height: size.height);
    } else if (size != _simulationSize) {
      _simulationSize = size;
      _simulation!.resize(width: size.width, height: size.height);
    }
    return true;
  }

  void _animateRain(Duration elapsed) {
    if (!_active || widget.reducedMotion || !_ensureSimulation()) return;
    final previous = _lastPhysicsFrame;
    if (previous != null &&
        elapsed - previous < const Duration(milliseconds: 32)) {
      return;
    }
    _lastPhysicsFrame = elapsed;
    if (previous != null) {
      _simulation!.advance(elapsed - previous);
    }
    unawaited(_sendDrops());
  }

  Future<void> _sendDrops() async {
    if (!_active || _sendingDrops || !_ensureSimulation()) return;
    _sendingDrops = true;
    try {
      await _channel.invokeMethod<void>('drops', {
        'data': _simulation!.packet,
        'width': _simulationSize.width,
        'height': _simulationSize.height,
      });
    } on MissingPluginException {
      _stopUnavailableEffect(missingPlugin: true);
    } on PlatformException catch (error) {
      if (error.code == 'rain_shader_unavailable') _stopUnavailableEffect();
      // A replaced or temporarily unavailable GL surface can recover next tick.
    } finally {
      _sendingDrops = false;
    }
  }

  void _stopUnavailableEffect({bool missingPlugin = false}) {
    _unavailable = true;
    _channelUnavailable = _channelUnavailable || missingPlugin;
    _timer?.cancel();
    _physicsTimer?.cancel();
    _configurationRetry?.cancel();
    if (!_channelUnavailable && mounted && widget.supported) {
      unawaited(
        _channel
            .invokeMethod<void>('configure', {
              'enabled': false,
              'opacity': widget.windowOpacity,
              'cornerRadius': _maximized ? 0.0 : widget.cornerRadius,
            })
            .catchError((Object _) {}),
      );
    }
  }

  Future<void> _readWindowShape() async {
    final revision = ++_windowShapeRevision;
    try {
      final maximized = await windowManager.isMaximized();
      final fullScreen = await windowManager.isFullScreen();
      if (!mounted || !widget.supported || revision != _windowShapeRevision) {
        return;
      }
      final square = maximized || fullScreen;
      if (_maximized != square) {
        _maximized = square;
        _configure();
      }
    } on MissingPluginException {
      // A Flutter-only preview has no native window geometry.
    } on PlatformException {
      // Window events can still update the shape after the initial read.
    }
  }

  Future<void> _capture() async {
    if (!mounted || !_active || _capturing) return;
    _capturing = true;
    final revision = _revision;
    ui.Image? image;
    try {
      // Reuse an already painted scene when Flutter is idle. endOfFrame would
      // otherwise schedule a completely unnecessary Flutter frame every 100 ms
      // even though the native compositor alone animates the rain.
      final binding = WidgetsBinding.instance;
      if (binding.hasScheduledFrame ||
          binding.schedulerPhase != SchedulerPhase.idle) {
        await binding.endOfFrame;
      }
      if (!mounted || !_active || revision != _revision) return;
      final boundary = _boundary.currentContext?.findRenderObject();
      if (boundary is! _RainRenderBoundary ||
          boundary.debugNeedsPaint ||
          boundary.size.isEmpty) {
        return;
      }
      final layer = boundary.captureLayer;
      if (layer == null) return;
      final size = boundary.size;
      if (_flutterPng == null ||
          !identical(layer, _capturedLayer) ||
          layer.revision != _capturedLayerRevision ||
          layer.hasLiveTextures ||
          size != _capturedSize) {
        final ratio = math.min(1.0, 2048 / math.max(size.width, size.height));
        final capture = boundary.toImage(pixelRatio: ratio);
        // toImage builds its scene synchronously, before waiting for GPU
        // readback. A newer paint during that wait must remain uncaptured.
        final capturedRevision = layer.revision;
        image = await capture;
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (!mounted || !_active || revision != _revision || png == null) {
          return;
        }
        _flutterPng = png.buffer.asUint8List(
          png.offsetInBytes,
          png.lengthInBytes,
        );
        _capturedLayer = layer;
        _capturedLayerRevision = capturedRevision;
        _capturedSize = size;
      }
      final editor = await widget.editorService?.captureRainTexture();
      if (!mounted || !_active || revision != _revision) return;
      await _channel.invokeMethod<void>('frame', {
        'png': _flutterPng!,
        ...?editor,
      });
      if (widget.reducedMotion) await _sendDrops();
    } on MissingPluginException {
      _stopUnavailableEffect(missingPlugin: true);
    } on PlatformException catch (error) {
      if (error.code == 'rain_shader_unavailable') _stopUnavailableEffect();
      // A texture is expendable; the next frame can recover independently.
    } on StateError {
      // A resized or detached render surface can disappear during capture.
    } on Exception {
      // Rasterization failures must never interrupt typing or opening a menu.
    } finally {
      image?.dispose();
      _capturing = false;
    }
  }

  @override
  void onWindowMinimize() {
    _minimized = true;
    _configure();
  }

  @override
  void onWindowRestore() {
    _minimized = false;
    _configure();
  }

  @override
  void onWindowMaximize() {
    ++_windowShapeRevision;
    _maximized = true;
    _configure();
  }

  @override
  void onWindowUnmaximize() {
    ++_windowShapeRevision;
    _maximized = false;
    _configure();
  }

  @override
  void onWindowEnterFullScreen() => onWindowMaximize();

  @override
  void onWindowLeaveFullScreen() => unawaited(_readWindowShape());

  @override
  void didChangeMetrics() {
    if (_active) unawaited(_capture());
  }

  @override
  void dispose() {
    ++_revision;
    ++_windowShapeRevision;
    _timer?.cancel();
    _configurationRetry?.cancel();
    _physicsTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.supported) {
      windowManager.removeListener(this);
    }
    _resetNative();
    super.dispose();
  }

  void _resetNative() {
    if (!_nativeConfigured) return;
    _nativeConfigured = false;
    unawaited(
      _channel
          .invokeMethod<void>('configure', {'enabled': false, 'opacity': 1.0})
          .catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) =>
      _RainBoundary(key: _boundary, child: widget.child);
}

/// Retains the same Flutter layer tree and pixels as RepaintBoundary. Its
/// composition revision also observes independently repainting descendant
/// boundaries and opacity/transform animations. Unfrozen external textures keep
/// their original sampling cadence even if they update outside Flutter frames.
class _RainBoundary extends SingleChildRenderObjectWidget {
  const _RainBoundary({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RainRenderBoundary();
}

class _RainRenderBoundary extends RenderRepaintBoundary {
  _RainCaptureLayer? get captureLayer => layer as _RainCaptureLayer?;

  @override
  OffsetLayer updateCompositedLayer({
    required covariant OffsetLayer? oldLayer,
  }) => oldLayer ?? _RainCaptureLayer();
}

class _RainCaptureLayer extends OffsetLayer {
  int revision = 0;
  bool hasLiveTextures = false;

  bool _hasLiveTexture(Layer layer) {
    if (layer is TextureLayer && !layer.freeze) return true;
    if (layer is ContainerLayer) {
      for (
        var child = layer.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        if (_hasLiveTexture(child)) return true;
      }
    }
    return false;
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    revision++;
    hasLiveTextures = _hasLiveTexture(this);
    super.addToScene(builder);
  }
}
