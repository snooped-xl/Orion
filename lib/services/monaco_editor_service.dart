import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Serves the bundled editor and workers on one offline, loopback origin.
class EditorAssetServer {
  EditorAssetServer({Directory? directory})
    : directory =
          directory ??
          Directory(
            '${File(Platform.resolvedExecutable).parent.path}/data/monaco',
          );

  final Directory directory;
  HttpServer? _server;
  Future<Uri> start() async {
    if (_server != null) {
      return Uri.parse('http://127.0.0.1:${_server!.port}/editor/index.html');
    }
    if (!await File('${directory.path}/index.html').exists()) {
      throw const FileSystemException('The bundled Monaco editor is missing.');
    }
    final server = _server ??= await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    server.listen(_serve);
    return Uri.parse('http://127.0.0.1:${server.port}/editor/index.html');
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Cross-Origin-Resource-Policy', 'same-origin');
    if (!['GET', 'HEAD'].contains(request.method) ||
        request.uri.pathSegments.isEmpty ||
        request.uri.pathSegments.first != 'editor') {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final segments = request.uri.pathSegments.skip(1).toList();
    if (segments.isEmpty ||
        segments.any(
          (s) =>
              s.isEmpty ||
              s == '.' ||
              s == '..' ||
              s.contains('/') ||
              s.contains('\\'),
        )) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final file = File('${directory.path}/${segments.join('/')}');
    try {
      if (!await file.exists()) {
        response.statusCode = HttpStatus.notFound;
      } else {
        final root = await directory.resolveSymbolicLinks();
        final target = await file.resolveSymbolicLinks();
        if (!target.startsWith('$root${Platform.pathSeparator}')) {
          response.statusCode = HttpStatus.notFound;
        } else {
          final extension = segments.last.split('.').last;
          response.headers.contentType = switch (extension) {
            'html' => ContentType.html,
            'js' ||
            'mjs' => ContentType('application', 'javascript', charset: 'utf-8'),
            'css' => ContentType('text', 'css', charset: 'utf-8'),
            'json' => ContentType.json,
            'ttf' => ContentType('font', 'ttf'),
            'woff' => ContentType('font', 'woff'),
            'woff2' => ContentType('font', 'woff2'),
            'svg' => ContentType('image', 'svg+xml'),
            _ => ContentType.binary,
          };
          response.contentLength = await file.length();
          if (request.method != 'HEAD') {
            await response.addStream(file.openRead());
          }
        }
      }
    } on FileSystemException {
      response.statusCode = HttpStatus.notFound;
    } finally {
      await response.close();
    }
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }
}

/// Coordinates real Monaco models with Flutter's persisted workspace.
class MonacoEditorService extends ChangeNotifier {
  /// Live frames bypass Flutter's global image cache and workspace listeners.
  /// RawImage clones the current handle; replacing it releases our old handle.
  ValueListenable<ui.Image?> get visualMirrorFrame => _visualMirrorFrame;
  bool get visualMirror => _visualMirror;

  /// Capture the real surface, including native syntax, selection and scroll.
  /// Blue also uses this directly for its separately dimmed navigation frame.
  Future<Uint8List?> capturePreview() {
    if (_disposed || !visible || !identical(_owner, this)) {
      return Future<Uint8List?>.value();
    }
    final inFlight = _previewCapture;
    if (inFlight != null) return inFlight;
    late final Future<Uint8List?> capture;
    capture = _captureFrame().whenComplete(() {
      if (identical(_previewCapture, capture)) _previewCapture = null;
    });
    _previewCapture = capture;
    return capture;
  }

  Future<Uint8List?> _captureFrame() async {
    final session = _nativeSession;
    final bytes = await _captureNativeFrame();
    if (_disposed || session != _nativeSession || !identical(_owner, this)) {
      return null;
    }
    if (bytes != null && bytes.isNotEmpty) {
      _frozenPreview = bytes;
      _notify();
      return bytes;
    }
    return null;
  }

  /// Keep the actual native request locked until it finishes. A caller timeout
  /// cannot cancel WebKit's snapshot and must never start overlapping work.
  Future<Uint8List?> _captureNativeFrame({int? maxDimension}) {
    var capture = _nativeCapture;
    if (capture == null) {
      final session = _nativeSession;
      final pixelCapture = _nativePixelCapture;
      late final Future<Uint8List?> request;
      request = (() async {
        try {
          // Frozen PNG previews and live pixels share WebKit's one snapshot
          // slot. A timeout never permits overlapping native requests.
          if (pixelCapture != null) await pixelCapture;
          if (_disposed ||
              session != _nativeSession ||
              !identical(_owner, this)) {
            return null;
          }
          final bytes = await _channel.invokeMethod<Uint8List>(
            'capturePreview',
            maxDimension == null ? null : {'maxDimension': maxDimension},
          );
          if (_disposed ||
              session != _nativeSession ||
              !identical(_owner, this)) {
            return null;
          }
          return bytes != null && bytes.isNotEmpty ? bytes : null;
        } on PlatformException {
          return null;
        } on MissingPluginException {
          return null;
        } finally {
          if (identical(_nativeCapture, request)) _nativeCapture = null;
        }
      })();
      capture = _nativeCapture = request;
    }
    // Menus and file pickers can still open when a renderer has stalled.
    return capture.timeout(const Duration(seconds: 1), onTimeout: () => null);
  }

  Future<Map<Object?, Object?>?> _captureNativePixels() {
    var capture = _nativePixelCapture;
    if (capture == null) {
      final session = _nativeSession;
      final pngCapture = _nativeCapture;
      late final Future<Map<Object?, Object?>?> request;
      request = (() async {
        try {
          if (pngCapture != null) await pngCapture;
          if (_disposed ||
              session != _nativeSession ||
              !identical(_owner, this)) {
            return null;
          }
          final result = await _channel.invokeMethod<Object?>(
            'capturePreviewPixels',
            {'frame': _lastMirrorPixelFrame},
          );
          if (_disposed ||
              session != _nativeSession ||
              !identical(_owner, this)) {
            return null;
          }
          if (result is! Map) return null;
          final width = result['width'], height = result['height'];
          final frame = result['frame'], pixels = result['pixels'];
          if (width is! int ||
              height is! int ||
              frame is! int ||
              width < 1 ||
              height < 1 ||
              width > 4096 ||
              height > 4096 ||
              width * height > 4 * 1024 * 1024 ||
              frame < 1 ||
              (pixels != null &&
                  (pixels is! Uint8List ||
                      pixels.length != width * height * 4))) {
            return null;
          }
          if (pixels == null &&
              (frame != _lastMirrorPixelFrame ||
                  _visualMirrorFrame.value?.width != width ||
                  _visualMirrorFrame.value?.height != height)) {
            return null;
          }
          return result;
        } on PlatformException {
          return null;
        } on MissingPluginException {
          if (session == _nativeSession) _pixelPreviewSupported = false;
          return null;
        } finally {
          if (identical(_nativePixelCapture, request)) {
            _nativePixelCapture = null;
          }
        }
      })();
      capture = _nativePixelCapture = request;
    }
    return capture.timeout(const Duration(seconds: 1), onTimeout: () => null);
  }

  Future<ui.Image> _decodePixels(Map<Object?, Object?> frame) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      frame['pixels'] as Uint8List,
    );
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: frame['width'] as int,
        height: frame['height'] as int,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      codec = await descriptor.instantiateCodec();
      return (await codec.getNextFrame()).image;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  /// Await before mounting Flutter chrome over the native WebKit child.
  /// Releasing this owner during capture cancels the pending hide, so a late
  /// native result cannot cover the editor after its menu has been dismissed.
  Future<void> freezeForOverlay({String owner = 'route'}) async {
    if (_disposed || _obscuredBy.contains(owner)) return;
    final request = Object();
    _pendingFreezes[owner] = request;
    _updateMirrorLoop();
    if (visible) await capturePreview();
    if (_disposed || !identical(_pendingFreezes[owner], request)) return;
    _pendingFreezes.remove(owner);
    setObscured(true, owner: owner);
  }

  Uint8List? get frozenPreview => _frozenPreview;

  /// A rain lens samples the live editor without changing overlay visibility,
  /// frozen previews, focus, or notifying the workspace on every texture frame.
  Future<Map<String, Object?>?> captureRainTexture() async {
    if (_disposed || !visible || !identical(_owner, this) || _mirrorIsPainted) {
      return null;
    }
    final bounds = _bounds;
    if (bounds == null) return null;
    final session = _nativeSession;
    try {
      final bytes = await _captureNativeFrame(
        maxDimension: _visualMirror ? null : 2048,
      );
      if (_disposed ||
          session != _nativeSession ||
          !visible ||
          _mirrorIsPainted ||
          !identical(_owner, this) ||
          !identical(_bounds, bounds) ||
          bytes == null ||
          bytes.isEmpty) {
        return null;
      }
      return {
        'editorPng': bytes,
        'editorX': bounds['x'],
        'editorY': bounds['y'],
        'editorWidth': bounds['width'],
        'editorHeight': bounds['height'],
      };
    } on TimeoutException {
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static MonacoEditorService? _owner;
  MonacoEditorService({
    MethodChannel? channel,
    EditorAssetServer? server,
    required this.onChange,
    required this.onShortcut,
  }) : _channel = channel ?? const MethodChannel('orion/monaco'),
       _server = server ?? EditorAssetServer();

  final MethodChannel _channel;
  final EditorAssetServer _server;
  final void Function(String id, String content) onChange;
  final void Function(String name) onShortcut;
  final Map<int, Completer<void>> _flushes = {};
  final Map<String, String> _nativeContent = {};
  Map<String, Object?>? _snapshot;
  Map? _renderedSnapshot;
  int _syncGeneration = 0;
  String? _activeId;
  String? _nativeTheme;
  bool _focusRequested = false;
  bool ready = false;
  bool initializing = false;
  String? error;
  int line = 1;
  int column = 1;
  int _sequence = 0;
  bool _disposed = false;
  bool _active = true;
  final Set<String> _obscuredBy = {};
  final Map<String, Object> _pendingFreezes = {};
  Uint8List? _frozenPreview;
  Future<Uint8List?>? _previewCapture;
  Future<Uint8List?>? _nativeCapture;
  Future<Map<Object?, Object?>?>? _nativePixelCapture;
  bool _pixelPreviewSupported = false;
  int _lastMirrorPixelFrame = 0;
  int _nativeSession = 0;
  final _visualMirrorFrame = ValueNotifier<ui.Image?>(null);
  Uint8List? _lastMirrorPng;
  final Set<Object> _mirrorPresentations = {};
  bool _visualMirror = false, _mirrorFocused = false, _mirrorCapturing = false;
  bool _mirrorFramePresented = false;
  bool _mirrorRefreshPending = true;
  bool _nativeVisualMirror = false;
  int _mirrorRevision = 0, _mirrorFailures = 0;
  Timer? _mirrorTimer, _mirrorActivity;
  Duration? _mirrorScheduledDelay;
  bool _visibilityNotifyQueued = false;
  bool _transitioning = false;
  bool _reducedMotion = false;
  bool _animateReveal = true;
  final Map<String, double> _opacityByOwner = {};
  double? _nativeOpacity;
  double _uiScale = 1;
  Map<String, Object?>? _bounds;
  String? _boundsJson;
  Completer<void>? _readySignal;

  bool get visible =>
      ready && _active && _obscuredBy.isEmpty && !_transitioning;

  Future<void> initialize() async {
    if (initializing || ready || _disposed) return;
    initializing = true;
    _nativeSession++;
    _syncGeneration++;
    _renderedSnapshot = null;
    _nativeCapture = null;
    _nativePixelCapture = null;
    _pixelPreviewSupported = false;
    _invalidateMirror(clear: true);
    _frozenPreview = null;
    error = null;
    _notify();
    _owner = this;
    _channel.setMethodCallHandler(_handleMessage);
    _readySignal = Completer<void>();
    try {
      final address = await _server.start();
      if (_disposed || !identical(_owner, this)) {
        await _server.close();
        return;
      }
      final capabilities = await _channel.invokeMethod<Object?>('create', {
        'url': address.toString(),
      });
      _pixelPreviewSupported =
          capabilities is Map && capabilities['pixelPreview'] == true;
      if (_disposed || !identical(_owner, this)) return;
      await _readySignal!.future.timeout(const Duration(seconds: 25));
      if (_disposed || !identical(_owner, this)) return;
      if (error != null) {
        throw PlatformException(code: 'host_error', message: error);
      }
      ready = true;
      _nativeVisualMirror = false;
      _nativeOpacity = null;
      if (_snapshot != null) await synchronize(_snapshot!);
      _boundsJson = null;
      await _pushBounds();
    } catch (failure) {
      if (!_disposed) {
        error =
            'Could not start Monaco. ${failure is PlatformException ? failure.message ?? failure.code : failure}';
        ready = false;
      }
    } finally {
      initializing = false;
      _updateMirrorLoop();
      _notify();
    }
  }

  Future<void> _handleMessage(MethodCall call) async {
    if (call.method != 'message' || _disposed) return;
    final Object? decoded = call.arguments is String
        ? jsonDecode(call.arguments as String)
        : call.arguments;
    if (decoded is! Map) return;
    switch (decoded['type']) {
      case 'ready':
        if (!(_readySignal?.isCompleted ?? true)) _readySignal!.complete();
      case 'change':
        _mirrorInteraction();
        final id = decoded['id'];
        final content = decoded['content'];
        if (id is String && content is String) {
          _syncGeneration++;
          _nativeContent[id] = content;
          _acknowledgeContent(id, content);
          onChange(id, content);
        }
      case 'cursor':
        _mirrorInteraction();
        final nextLine = (decoded['line'] as num?)?.toInt() ?? 1;
        final nextColumn = (decoded['column'] as num?)?.toInt() ?? 1;
        if (line != nextLine || column != nextColumn) {
          line = nextLine;
          column = nextColumn;
          _notify();
        }
      case 'focus':
        _mirrorFocused = decoded['focused'] == true;
        _updateMirrorLoop();
      case 'interaction':
        _mirrorInteraction();
      case 'shortcut':
        final name = decoded['name'];
        if (name is String) onShortcut(name);
      case 'flush':
        final id = decoded['id'];
        final content = decoded['content'];
        if (id is String && content is String) {
          _syncGeneration++;
          _nativeContent[id] = content;
          _acknowledgeContent(id, content);
          onChange(id, content);
        }
        _flushes.remove(decoded['requestId'])?.complete();
      case 'error':
        error = '${decoded['message'] ?? 'Editor error'}';
        _notify();
      case 'hostError':
        _nativeSession++;
        _syncGeneration++;
        _renderedSnapshot = null;
        _nativeCapture = null;
        _nativePixelCapture = null;
        _pixelPreviewSupported = false;
        _invalidateMirror(clear: true);
        _frozenPreview = null;
        error = '${decoded['message'] ?? 'The editor renderer stopped.'}';
        ready = false;
        _boundsJson = null;
        _activeId = null;
        _nativeTheme = null;
        _nativeOpacity = null;
        _focusRequested = true;
        if (!(_readySignal?.isCompleted ?? true)) _readySignal!.complete();
        for (final pending in _flushes.values) {
          if (!pending.isCompleted) pending.complete();
        }
        if (identical(_owner, this)) {
          unawaited(
            _channel
                .invokeMethod<void>('setVisible', false)
                .catchError((Object _) {}),
          );
        }
        _notify();
    }
  }

  Future<void> synchronize(Map<String, Object?> snapshot) async {
    final generation = ++_syncGeneration;
    _snapshot = snapshot;
    final options = snapshot['options'];
    final mirror = options is Map && options['compositorGlass'] == true;
    if (_visualMirror != mirror) {
      _visualMirror = mirror;
      _mirrorFocused = false;
      if (!mirror) {
        _mirrorActivity?.cancel();
        _mirrorActivity = null;
      }
      _invalidateMirror(clear: true);
      // This can run while the workspace builds; defer ordinary listeners.
      _notifyVisibility();
      if (!mirror) unawaited(_pushVisualMirror(false));
    }
    _reducedMotion = options is Map && options['reducedMotion'] == true;
    _animateReveal = options is! Map || options['animateReveal'] != false;
    final uiScale = options is Map ? options['uiScale'] : null;
    final previousScale = _uiScale;
    _uiScale = uiScale is num && uiScale.isFinite
        ? uiScale.toDouble().clamp(.8, 1.25)
        : 1;
    if (previousScale != _uiScale) _invalidateMirror();
    final documents = snapshot['documents'];
    if (!ready || _disposed || !identical(_owner, this)) return;
    final needsTheme =
        options is Map &&
        options['brightness'] is String &&
        options['brightness'] != _nativeTheme;
    // Editor-originated changes already exist in WebKit. Compare against its
    // acknowledged models before serializing: echoing every complete document
    // back on each key or cursor update reconfigured the entire editor.
    if (!needsTheme && _sameJson(_renderedSnapshot, snapshot)) return;
    // An acknowledgement of an editor-originated edit must never replace newer
    // keystrokes already in Monaco while the platform message is in flight.
    final encoded = jsonEncode({
      'type': 'sync',
      ...snapshot,
      if (documents is List)
        'documents': [
          for (final document in documents)
            if (document is Map)
              {
                ...document,
                if (document['content'] == _nativeContent[document['id']])
                  'nativeEcho': true,
              }
            else
              document,
        ],
    });
    if (documents is List) {
      final ids = documents
          .whereType<Map>()
          .map((document) => document['id'])
          .toSet();
      _nativeContent.removeWhere((id, _) => !ids.contains(id));
    }
    if (!ready || _disposed || !identical(_owner, this)) {
      return;
    }
    if (_activeId != snapshot['activeId']) {
      _activeId = snapshot['activeId'] as String?;
      _focusRequested = true;
    }
    Map? sentSnapshot;
    try {
      if (options is Map &&
          options['brightness'] is String &&
          options['brightness'] != _nativeTheme) {
        _nativeTheme = options['brightness'] as String;
        await _channel.invokeMethod<void>('setTheme', _nativeTheme != 'light');
      }
      if (_disposed ||
          !identical(_owner, this) ||
          generation != _syncGeneration) {
        return;
      }
      _renderedSnapshot = sentSnapshot = _copyJson(snapshot) as Map;
      await _channel.invokeMethod<void>('send', encoded);
      if (_disposed ||
          !identical(_owner, this) ||
          generation != _syncGeneration) {
        return;
      }
      await _pushBounds();
      if (generation == _syncGeneration && error != null) {
        error = null;
        _notify();
      }
      _mirrorInteraction();
    } on PlatformException catch (failure) {
      // A failed send was never acknowledged by the renderer. Retain newer
      // requests, but allow this exact snapshot to be retried, including when
      // native typing advanced the generation during the failed platform call.
      final failedCurrentSnapshot =
          sentSnapshot != null && identical(_renderedSnapshot, sentSnapshot);
      if (failedCurrentSnapshot) _renderedSnapshot = null;
      if (_disposed ||
          !identical(_owner, this) ||
          (generation != _syncGeneration && !failedCurrentSnapshot)) {
        return;
      }
      _nativeTheme = null;
      final message = failure.message ?? failure.code;
      if (error != message) {
        error = message;
        _notify();
      }
    }
  }

  void _acknowledgeContent(String id, String content) {
    final documents = _renderedSnapshot?['documents'];
    if (documents is! List) return;
    for (final document in documents) {
      if (document is Map && document['id'] == id) {
        document['content'] = content;
        return;
      }
    }
  }

  static bool _sameJson(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.entries.every(
            (entry) =>
                b.containsKey(entry.key) &&
                _sameJson(entry.value, b[entry.key]),
          );
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameJson(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  static Object? _copyJson(Object? value) => switch (value) {
    Map value => {
      for (final entry in value.entries) entry.key: _copyJson(entry.value),
    },
    List value => [for (final item in value) _copyJson(item)],
    _ => value,
  };

  Future<void> action(String name, {String? text}) async {
    if (!ready || _disposed || !identical(_owner, this)) return;
    await _channel.invokeMethod<void>(
      'send',
      jsonEncode({'type': 'action', 'name': name, 'text': ?text}),
    );
    _focusRequested = true;
    await _pushBounds();
  }

  Future<void> flush() async {
    if (!ready || _disposed || !identical(_owner, this)) return;
    final requestId = ++_sequence;
    final pending = Completer<void>();
    _flushes[requestId] = pending;
    try {
      await _channel.invokeMethod<void>(
        'send',
        jsonEncode({'type': 'flush', 'requestId': requestId}),
      );
      await pending.future.timeout(const Duration(seconds: 3));
      if (!ready && error != null) {
        throw PlatformException(code: 'host_error', message: error);
      }
    } finally {
      _flushes.remove(requestId);
    }
  }

  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _invalidateMirror();
    unawaited(_pushBounds());
    _notifyVisibility();
  }

  /// Source shell fades multiply independently, so disposal of the previous
  /// interface cannot cancel a newly mounted interface's animation.
  void setOpacity(double opacity, {String owner = 'shell'}) {
    if (!opacity.isFinite || _disposed) return;
    final value = opacity.clamp(0.0, 1.0);
    if (value == 1) {
      if (_opacityByOwner.remove(owner) == null) return;
    } else {
      if (_opacityByOwner[owner] == value) return;
      _opacityByOwner[owner] = value;
    }
    unawaited(_pushOpacity());
  }

  Future<void> _pushOpacity() async {
    if (!ready || _disposed || !identical(_owner, this)) return;
    final value = _opacityByOwner.values.fold<double>(1, (a, b) => a * b);
    if (_nativeOpacity == value) return;
    _nativeOpacity = value;
    await _channel.invokeMethod<void>('setOpacity', value);
  }

  void setObscured(bool obscured, {String owner = 'route'}) {
    if (_disposed) return;
    if (!obscured) _pendingFreezes.remove(owner);
    final changed = obscured
        ? _obscuredBy.add(owner)
        : _obscuredBy.remove(owner);
    if (changed) {
      _invalidateMirror();
      if (!obscured) _focusRequested = true;
      unawaited(_pushBounds());
      _notifyVisibility();
    } else {
      _updateMirrorLoop();
    }
  }

  void setTransitioning(bool value) {
    if (_transitioning == value) return;
    _transitioning = value;
    _invalidateMirror();
    unawaited(_pushBounds());
    _notifyVisibility();
  }

  Future<void> setBounds({
    required double x,
    required double y,
    required double width,
    required double height,
  }) async {
    final bounds = {'x': x, 'y': y, 'width': width, 'height': height};
    if (!mapEquals(_bounds, bounds)) {
      _bounds = bounds;
      _invalidateMirror();
    }
    await _pushBounds();
    _updateMirrorLoop();
  }

  Future<void> _pushBounds() async {
    if (!ready || _disposed || !identical(_owner, this)) return;
    // Visibility updates must reach GTK immediately, including modal hides.
    // The channel orders this opacity call before the bounds call below.
    unawaited(_pushOpacity());
    final bounds = {
      ...?_bounds,
      'visible': visible && _bounds != null,
      // Source shells drive their exact page fade through opacity owners;
      // adding Orion's GTK reveal would delay their code relative to chrome.
      'reducedMotion': _reducedMotion || !_animateReveal,
      'uiScale': _uiScale,
    };
    final encoded = jsonEncode(bounds);
    if (encoded != _boundsJson) {
      _boundsJson = encoded;
      if (_bounds == null) {
        await _channel.invokeMethod<void>('setVisible', false);
      } else {
        await _channel.invokeMethod<void>('setBounds', bounds);
      }
    }
    if (visible && _bounds != null && _focusRequested) {
      _focusRequested = false;
      await _channel.invokeMethod<void>('focus');
    }
    _updateMirrorLoop();
  }

  /// A mounted editor reports lifecycle and TickerMode without changing native
  /// focus or visibility. Hidden/minimized pages do no continuous capture work.
  void setMirrorPresentationActive(bool active, {required Object owner}) {
    if (_disposed) return;
    final changed = active
        ? _mirrorPresentations.add(owner)
        : _mirrorPresentations.remove(owner);
    if (changed) _invalidateMirror();
  }

  /// Suppress native painting only after this exact image reached Flutter's
  /// frame. Until then the original WebKit surface continues displaying code.
  void mirrorFramePresented(ui.Image image) {
    if (!_mirrorShouldRun ||
        !identical(_visualMirrorFrame.value, image) ||
        _mirrorFramePresented) {
      return;
    }
    _mirrorFramePresented = true;
    unawaited(_pushVisualMirror(true));
  }

  bool get _mirrorShouldRun =>
      !_disposed &&
      identical(_owner, this) &&
      _visualMirror &&
      visible &&
      _bounds != null &&
      (_bounds!['width'] as double) > 0 &&
      (_bounds!['height'] as double) > 0 &&
      _mirrorPresentations.isNotEmpty &&
      _pendingFreezes.isEmpty;

  // The rain compositor already receives RawImage in its Flutter frame. Adding
  // a second native snapshot would darken glyph edges and ghost moving code.
  bool get _mirrorIsPainted => _visualMirror && _mirrorFramePresented;

  void _invalidateMirror({bool clear = false}) {
    _mirrorRevision++;
    _mirrorRefreshPending = true;
    _mirrorTimer?.cancel();
    _mirrorTimer = null;
    _mirrorScheduledDelay = null;
    if (clear) {
      _mirrorFramePresented = false;
      _mirrorFailures = 0;
      _replaceMirrorFrame(null);
    }
    _updateMirrorLoop();
  }

  void _replaceMirrorFrame(ui.Image? image) {
    final previous = _visualMirrorFrame.value;
    if (identical(previous, image)) return;
    _visualMirrorFrame.value = image;
    if (image == null) {
      _lastMirrorPng = null;
      _lastMirrorPixelFrame = 0;
    }
    previous?.dispose();
  }

  Future<void> _pushVisualMirror(bool enabled) async {
    if (!ready || _disposed || !identical(_owner, this)) return;
    if (_nativeVisualMirror == enabled) return;
    _nativeVisualMirror = enabled;
    try {
      await _channel.invokeMethod<void>('setVisualMirror', enabled);
    } on PlatformException {
      _nativeVisualMirror = false;
    } on MissingPluginException {
      _nativeVisualMirror = false;
    }
  }

  void _mirrorInteraction() {
    if (!_visualMirror || _disposed) return;
    _mirrorActivity?.cancel();
    _mirrorActivity = Timer(const Duration(milliseconds: 600), () {
      _mirrorActivity = null;
      _updateMirrorLoop();
    });
    _updateMirrorLoop();
  }

  void _updateMirrorLoop() {
    if (!_mirrorShouldRun) {
      _mirrorTimer?.cancel();
      _mirrorTimer = null;
      _mirrorScheduledDelay = null;
      return;
    }
    if (_mirrorCapturing) return;
    final delay =
        _mirrorRefreshPending ||
            _visualMirrorFrame.value == null ||
            _mirrorActivity != null
        ? const Duration(milliseconds: 16)
        : _mirrorFocused
        ? const Duration(milliseconds: 50)
        : const Duration(milliseconds: 250);
    if (_mirrorTimer != null &&
        (_mirrorScheduledDelay ?? Duration.zero) <= delay) {
      return;
    }
    _mirrorTimer?.cancel();
    _mirrorScheduledDelay = delay;
    _mirrorTimer = Timer(delay, () {
      _mirrorTimer = null;
      _mirrorScheduledDelay = null;
      unawaited(_captureMirrorFrame());
    });
  }

  Future<void> _captureMirrorFrame() async {
    if (!_mirrorShouldRun || _mirrorCapturing) return;
    _mirrorCapturing = true;
    final revision = _mirrorRevision;
    ui.Codec? codec;
    ui.Image? image;
    try {
      if (_pixelPreviewSupported) {
        final frame = await _captureNativePixels();
        if (!_mirrorShouldRun || revision != _mirrorRevision) return;
        if (frame != null) {
          if (frame['pixels'] != null) {
            image = await _decodePixels(frame);
            if (!_mirrorShouldRun || revision != _mirrorRevision) return;
            _replaceMirrorFrame(image);
            image = null;
          }
          _lastMirrorPixelFrame = frame['frame'] as int;
          _lastMirrorPng = null;
          _mirrorFailures = 0;
          _mirrorRefreshPending = false;
          return;
        }
      }
      final bytes = await _captureNativeFrame();
      if (!_mirrorShouldRun || revision != _mirrorRevision) return;
      if (bytes == null) {
        _mirrorFailures++;
      } else if (_visualMirrorFrame.value != null &&
          listEquals(bytes, _lastMirrorPng)) {
        // Native's lossless cache often returns the exact same PNG while the
        // caret is steady. Keep the existing GPU image and texture alive.
        _mirrorFailures = 0;
        _mirrorRefreshPending = false;
      } else {
        codec = await ui.instantiateImageCodec(bytes);
        image = (await codec.getNextFrame()).image;
        if (!_mirrorShouldRun || revision != _mirrorRevision) return;
        _mirrorFailures = 0;
        _mirrorRefreshPending = false;
        _lastMirrorPng = bytes;
        _lastMirrorPixelFrame = 0;
        _replaceMirrorFrame(image);
        image = null;
      }
    } catch (_) {
      // A malformed or unavailable snapshot must leave native Monaco usable.
      _mirrorFailures++;
    } finally {
      image?.dispose();
      codec?.dispose();
      if (_mirrorFailures >= 3 && revision == _mirrorRevision) {
        _mirrorFramePresented = false;
        unawaited(_pushVisualMirror(false));
        _replaceMirrorFrame(null);
      }
      _mirrorCapturing = false;
      _updateMirrorLoop();
    }
  }

  void _notifyVisibility() {
    if (_disposed || _visibilityNotifyQueued) return;
    _visibilityNotifyQueued = true;
    scheduleMicrotask(() {
      _visibilityNotifyQueued = false;
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _nativeSession++;
    _mirrorRevision++;
    _mirrorTimer?.cancel();
    _mirrorActivity?.cancel();
    _replaceMirrorFrame(null);
    _visualMirrorFrame.dispose();
    _pendingFreezes.clear();
    _frozenPreview = null;
    if (!(_readySignal?.isCompleted ?? true)) _readySignal!.complete();
    if (identical(_owner, this)) {
      _owner = null;
      _channel.setMethodCallHandler(null);
      unawaited(
        _channel.invokeMethod<void>('dispose').catchError((Object _) {}),
      );
    }
    for (final pending in _flushes.values) {
      if (!pending.isCompleted) pending.complete();
    }
    _flushes.clear();
    unawaited(_server.close());
    super.dispose();
  }
}
