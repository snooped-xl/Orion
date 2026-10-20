import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/bridge_models.dart';

/// Client for RelapseGtk's local protocol. This is deliberately separate from
/// OrionBridgeService: Relapse owns the Unix socket and Orion only connects to
/// it when the Linux-only compatibility setting is enabled.
class RelapseGtkService extends ChangeNotifier {
  RelapseGtkService({
    this.socketPath = defaultSocketPath,
    this.reconnectInterval = const Duration(seconds: 1),
    Future<String> Function()? outputScriptLoader,
    this.maximumScriptBytes = 2 * 1024 * 1024,
  }) : _outputScriptLoader =
           outputScriptLoader ??
           (() =>
               rootBundle.loadString('assets/relapsegtk/output_capture.luau'));

  static const defaultSocketPath = '/tmp/relapse.sock';
  static const mainChannel = '@main';
  static const outputChannel = 'relapsegtk.output.v1';
  static const protocolVersion = 1;

  final String socketPath;
  final Duration reconnectInterval;
  final int maximumScriptBytes;
  final Future<String> Function() _outputScriptLoader;
  final _logs = StreamController<BridgeLogEntry>.broadcast(sync: true);

  _RelapseChannel? _main;
  _RelapseChannel? _output;
  Timer? _reconnectTimer;
  Timer? _outputRetryTimer;
  DateTime? _outputRetryDeadline;
  bool _enabled = false;
  bool _disposed = false;
  bool _connecting = false;
  bool _outputConnecting = false;
  bool _mainHelloReceived = false;
  bool _connected = false;
  bool _ready = false;
  bool _outputDesired = false;
  bool _outputSubscribed = false;
  bool _outputTimeoutReported = false;
  String? _error;
  int? _session;
  int _nextScriptId = 1;
  int? _captureScriptId;
  int? _captureSession;
  final Map<int, String> _scriptNames = {};

  Stream<BridgeLogEntry> get logReceived => _logs.stream;
  bool get enabled => _enabled;
  bool get isConnected => _connected;
  bool get isReady => _connected && _ready;
  bool get isActive => _enabled;
  bool get outputCaptureActive => _outputSubscribed;
  int? get session => _session;
  String? get error => _error;

  Future<void> start() async {
    if (_disposed || _enabled) return;
    _enabled = true;
    _error = null;
    _reconnectTimer = Timer.periodic(reconnectInterval, (_) {
      unawaited(_connectMain());
    });
    notifyListeners();
    await _connectMain();
  }

  Future<void> stop() async {
    if (!_enabled && _main == null && _output == null) return;
    _enabled = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopOutputRetries();
    _outputDesired = false;
    final output = _output;
    _output = null;
    _outputSubscribed = false;
    await output?.close();
    final main = _main;
    _main = null;
    await main?.close();
    _connected = false;
    _ready = false;
    _session = null;
    _mainHelloReceived = false;
    _error = null;
    _captureScriptId = null;
    _captureSession = null;
    _scriptNames.clear();
    if (!_disposed) notifyListeners();
  }

  Future<int> execute(String source, {required String name}) async {
    if (!isReady || _main == null) {
      throw StateError('Relapse is not connected to a ready game session.');
    }
    if (utf8.encode(source).length > maximumScriptBytes) {
      throw ArgumentError('Script exceeds the $maximumScriptBytes byte limit.');
    }
    final id = _nextScriptId++;
    final cleanName = name.trim();
    final scriptName = cleanName.isNotEmpty && cleanName.length <= 255
        ? cleanName
        : 'editor.luau';
    _scriptNames[id] = scriptName;
    try {
      _main!.send({
        'op': 'execute',
        'script_id': id,
        'session': _session,
        'name': scriptName,
        'source': source,
      });
    } on Object {
      _scriptNames.remove(id);
      rethrow;
    }
    return id;
  }

  Future<void> _connectMain() async {
    if (!_enabled || _disposed || _connecting || _main != null) return;
    _connecting = true;
    _mainHelloReceived = false;
    try {
      late final _RelapseChannel channel;
      channel = await _RelapseChannel.connect(
        socketPath: socketPath,
        channelName: mainChannel,
        onMessage: _onMainMessage,
        onClosed: _onMainClosed,
      );
      if (!_enabled || _disposed) {
        await channel.close();
        return;
      }
      if (!channel.isOpen) {
        throw const SocketException('Relapse closed during channel setup.');
      }
      _main = channel;
      _error = null;
      notifyListeners();
    } on Object catch (error) {
      if (_enabled && !_disposed) {
        _connected = false;
        _ready = false;
        _session = null;
        _error = _safeDetail(error.toString());
        notifyListeners();
      }
    } finally {
      _connecting = false;
    }
  }

  void _onMainClosed(_RelapseChannel channel, [Object? error]) {
    if (!identical(_main, channel)) return;
    _main = null;
    _connected = false;
    _ready = false;
    _session = null;
    _mainHelloReceived = false;
    _outputDesired = false;
    _stopOutputRetries();
    final output = _output;
    _output = null;
    _outputSubscribed = false;
    if (output != null) unawaited(output.close());
    if (error != null) _error = _safeDetail(error.toString());
    if (_enabled && !_disposed) notifyListeners();
  }

  void _onMainMessage(_RelapseChannel channel, Map<String, dynamic> message) {
    if (_main != null && !identical(_main, channel)) return;
    final type = message['type'];
    if (!_mainHelloReceived && type != 'hello') {
      _protocolError('Relapse did not begin with a hello message.');
      return;
    }
    if (_mainHelloReceived && type == 'hello') {
      _protocolError('Relapse sent more than one hello message.');
      return;
    }
    if (type == 'hello' || type == 'status') {
      final ready = message['ready'];
      final session = message['session'];
      if (ready is! bool ||
          session is! int ||
          session < 0 ||
          (ready && session == 0)) {
        _protocolError('Relapse sent an invalid session status.');
        return;
      }
      final previousSession = _session;
      _mainHelloReceived = true;
      _connected = true;
      _ready = ready;
      _session = session;
      _error = null;
      if (ready && (previousSession != session || _captureSession != session)) {
        _beginOutputCapture(session);
      } else if (!ready) {
        _outputDesired = false;
        _stopOutputRetries();
        final output = _output;
        _output = null;
        _outputSubscribed = false;
        if (output != null) unawaited(output.close());
      }
      notifyListeners();
      return;
    }
    if (type == 'exec_result') {
      final id = message['script_id'];
      final phase = message['phase'];
      if (id is! int || (phase != 'submitted' && phase != 'error')) {
        _protocolError('Relapse sent an invalid script result.');
        return;
      }
      final name = _scriptNames.remove(id) ?? 'Relapse output capture';
      if (id == _captureScriptId) {
        _captureScriptId = null;
        if (phase == 'error') {
          _outputDesired = false;
          _stopOutputRetries();
          _emitLog(
            'error',
            'Could not enable output capture: ${_safeDetail(message['detail']?.toString() ?? 'request failed')}',
          );
        }
        return;
      }
      _emitLog(
        phase == 'submitted' ? 'success' : 'error',
        phase == 'submitted'
            ? '$name submitted to Relapse.'
            : '$name failed: ${_safeDetail(message['detail']?.toString() ?? 'request failed')}',
        executionId: 'relapse_$id',
      );
      return;
    }
    if (type == 'log') {
      final level = message['level'];
      final text = message['text'];
      if (level is! String || text is! String) {
        _protocolError('Relapse sent an invalid log entry.');
        return;
      }
      _emitLog(level, text);
      return;
    }
    if (type == 'error') {
      _emitLog(
        'error',
        _safeDetail(message['detail']?.toString() ?? 'Request failed'),
      );
    }
  }

  void _beginOutputCapture(int session) {
    if (_captureSession == session && _outputDesired) return;
    _captureSession = session;
    _captureScriptId = null;
    _outputDesired = false;
    _outputSubscribed = false;
    _stopOutputRetries();
    unawaited(_sendOutputCaptureScript(session));
  }

  Future<void> _sendOutputCaptureScript(int session) async {
    try {
      final source = await _outputScriptLoader();
      if (!_enabled || !_ready || _session != session || _main == null) return;
      final id = _nextScriptId++;
      _captureScriptId = id;
      _scriptNames[id] = 'Relapse output capture';
      _main!.send({
        'op': 'execute',
        'script_id': id,
        'session': session,
        'name': 'relapsegtk-output.luau',
        'source': source,
      });
      _outputDesired = true;
      _startOutputRetries();
    } on Object catch (error) {
      _emitLog(
        'error',
        'Could not prepare Relapse output capture: ${_safeDetail(error.toString())}',
      );
    }
  }

  void _startOutputRetries() {
    _outputRetryTimer?.cancel();
    _outputRetryDeadline = DateTime.now().add(const Duration(seconds: 10));
    _outputTimeoutReported = false;
    _outputRetryTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (_outputSubscribed || !_outputDesired || !_ready || !_enabled) {
        _stopOutputRetries();
        return;
      }
      if (DateTime.now().isAfter(_outputRetryDeadline!)) {
        _stopOutputRetries();
        if (!_outputTimeoutReported) {
          _outputTimeoutReported = true;
          _emitLog(
            'warn',
            'Relapse is connected, but output capture did not start.',
          );
        }
        return;
      }
      unawaited(_connectOutput());
    });
    unawaited(_connectOutput());
  }

  void _stopOutputRetries() {
    _outputRetryTimer?.cancel();
    _outputRetryTimer = null;
    _outputRetryDeadline = null;
  }

  Future<void> _connectOutput() async {
    if (!_enabled ||
        !_ready ||
        !_outputDesired ||
        _output != null ||
        _outputConnecting) {
      return;
    }
    _outputConnecting = true;
    try {
      late final _RelapseChannel channel;
      channel = await _RelapseChannel.connect(
        socketPath: socketPath,
        channelName: outputChannel,
        onMessage: _onOutputMessage,
        onClosed: _onOutputClosed,
        timeout: const Duration(milliseconds: 250),
      );
      if (!_enabled || !_ready || !_outputDesired) {
        await channel.close();
        return;
      }
      if (!channel.isOpen) {
        throw const SocketException(
          'Relapse output channel closed during setup.',
        );
      }
      _output = channel;
      channel.send({'op': 'subscribe', 'version': protocolVersion});
    } on Object {
      // The executor creates this channel only after the output helper has
      // started. The short reconnect timer handles that startup race.
    } finally {
      _outputConnecting = false;
    }
  }

  void _onOutputClosed(_RelapseChannel channel, [Object? error]) {
    if (!identical(_output, channel)) return;
    _output = null;
    _outputSubscribed = false;
    if (_enabled && _ready && _outputDesired) _startOutputRetries();
    notifyListeners();
  }

  void _onOutputMessage(_RelapseChannel channel, Map<String, dynamic> message) {
    if (!identical(_output, channel)) return;
    final type = message['type'];
    if (type == 'subscribed') {
      if (message['version'] != protocolVersion) {
        _outputProtocolError(
          'Relapse output channel version is not supported.',
        );
        return;
      }
      _outputSubscribed = true;
      _outputTimeoutReported = false;
      _stopOutputRetries();
      notifyListeners();
      return;
    }
    if (type == 'failed') {
      _emitLog(
        'error',
        'Relapse output capture failed: ${_safeDetail(message['detail']?.toString() ?? 'request failed')}',
      );
      _outputDesired = false;
      _stopOutputRetries();
      unawaited(channel.close());
      return;
    }
    if (type == 'dropped') {
      final count = message['count'];
      if (count is! int || count < 1) {
        _outputProtocolError('Relapse sent an invalid dropped-message count.');
      } else {
        _emitLog('warn', '$count output messages were dropped by Relapse.');
      }
      return;
    }
    if (type == 'output') {
      final entries = message['entries'];
      final dropped = message['dropped'];
      // Relapse registers the peer before it writes the subscription ack. A
      // print from the game can therefore race that ack on the output socket.
      // The request has already been sent on this channel, so a valid batch is
      // sufficient proof that output capture is active.
      if (!_outputDesired ||
          entries is! List ||
          entries.isEmpty ||
          entries.length > 32 ||
          dropped is! int ||
          dropped < 0) {
        _outputProtocolError('Relapse sent an invalid output batch.');
        return;
      }
      final validatedEntries = <MapEntry<String, String>>[];
      for (final rawEntry in entries) {
        if (rawEntry is! Map ||
            rawEntry['text'] is! String ||
            rawEntry['level'] is! String) {
          _outputProtocolError('Relapse sent an invalid output entry.');
          return;
        }
        final level = rawEntry['level'] as String;
        final text = rawEntry['text'] as String;
        if (!const {'print', 'warn', 'error', 'info'}.contains(level) ||
            utf8.encode(text).length > 4096) {
          _outputProtocolError('Relapse sent an unsupported output entry.');
          return;
        }
        validatedEntries.add(MapEntry(level, text));
      }
      if (!_outputSubscribed) {
        _outputSubscribed = true;
        _outputTimeoutReported = false;
        _stopOutputRetries();
        notifyListeners();
      }
      if (dropped > 0) {
        _emitLog('warn', '$dropped output messages were dropped by Relapse.');
      }
      for (final entry in validatedEntries) {
        _emitLog(entry.key, entry.value);
      }
    }
  }

  void _protocolError(String detail) {
    _error = detail;
    _emitLog('error', detail);
    final main = _main;
    if (main != null) unawaited(main.close());
    final output = _output;
    if (output != null) unawaited(output.close());
  }

  /// An output-capture protocol issue must not tear down the execution
  /// channel. Keep the Relapse session usable and stop retrying this capture
  /// stream until the next session starts.
  void _outputProtocolError(String detail) {
    _outputDesired = false;
    _outputSubscribed = false;
    _stopOutputRetries();
    final output = _output;
    _output = null;
    if (output != null) unawaited(output.close());
    _emitLog('error', detail);
    if (!_disposed) notifyListeners();
  }

  void _emitLog(String level, String message, {String? executionId}) {
    final clean = _safeDetail(message);
    if (_logs.isClosed) return;
    _logs.add(
      BridgeLogEntry(
        timestampUtc: DateTime.now().toUtc(),
        level: level,
        message: clean,
        identifier: 'Relapse',
        executionId: executionId,
      ),
    );
  }

  static String _safeDetail(String value) {
    final clean = value.replaceAll(
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'),
      '',
    );
    return clean.length <= 4096 ? clean : clean.substring(0, 4096);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(stop());
    unawaited(_logs.close());
    super.dispose();
  }
}

typedef _RelapseMessageHandler =
    void Function(_RelapseChannel channel, Map<String, dynamic> message);
typedef _RelapseClosedHandler =
    void Function(_RelapseChannel channel, [Object? error]);

/// One length-prefixed JSON stream using RelapseGtk's channel handshake.
class _RelapseChannel {
  _RelapseChannel._(
    this._socket, {
    required _RelapseMessageHandler onMessage,
    required _RelapseClosedHandler onClosed,
  }) : _onMessage = onMessage,
       _onClosed = onClosed {
    _subscription = _socket.listen(
      _onData,
      onError: (Object error, StackTrace stack) => _finish(error),
      onDone: _finish,
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final _RelapseMessageHandler _onMessage;
  final _RelapseClosedHandler _onClosed;
  final List<int> _pending = [];
  final Completer<void> _opened = Completer<void>();
  late final StreamSubscription<Uint8List> _subscription;
  int _maximumMessageBytes = 8 * 1024 * 1024;
  bool _isOpen = false;
  bool _closed = false;
  bool get isOpen => _isOpen && !_closed;

  static Future<_RelapseChannel> connect({
    required String socketPath,
    required String channelName,
    required _RelapseMessageHandler onMessage,
    required _RelapseClosedHandler onClosed,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final socket = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
      timeout: timeout,
    );
    final channel = _RelapseChannel._(
      socket,
      onMessage: onMessage,
      onClosed: onClosed,
    );
    channel._write({
      'version': RelapseGtkService.protocolVersion,
      'channel': channelName,
    });
    try {
      await channel._opened.future.timeout(const Duration(seconds: 5));
      return channel;
    } on Object {
      await channel.close();
      rethrow;
    }
  }

  void send(Map<String, Object?> message) {
    if (!_isOpen || _closed) throw StateError('Relapse channel is closed.');
    _write(message);
  }

  void _write(Map<String, Object?> message) {
    final encoded = utf8.encode(jsonEncode(message));
    if (encoded.length > _maximumMessageBytes) {
      throw ArgumentError('Relapse message exceeds the negotiated size limit.');
    }
    final frame = Uint8List(encoded.length + 4);
    ByteData.sublistView(frame).setUint32(0, encoded.length, Endian.big);
    frame.setRange(4, frame.length, encoded);
    _socket.add(frame);
    unawaited(_socket.flush());
  }

  void _onData(Uint8List chunk) {
    if (_closed) return;
    _pending.addAll(chunk);
    while (_pending.length >= 4) {
      final length = ByteData.sublistView(
        Uint8List.fromList(_pending.sublist(0, 4)),
      ).getUint32(0, Endian.big);
      if (length > _maximumMessageBytes) {
        _finish(const FormatException('Relapse frame exceeds 8 MiB.'));
        return;
      }
      if (_pending.length < length + 4) return;
      final bytes = Uint8List.fromList(_pending.sublist(4, 4 + length));
      _pending.removeRange(0, 4 + length);
      try {
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) {
          throw const FormatException('Expected a JSON object.');
        }
        final message = Map<String, dynamic>.from(decoded);
        if (!_isOpen) {
          if (message['ok'] != true ||
              message['version'] != RelapseGtkService.protocolVersion ||
              message['max_message_bytes'] is! int ||
              (message['max_message_bytes'] as int) < 1) {
            throw FormatException(
              message['error'] is String
                  ? message['error'] as String
                  : 'Invalid Relapse channel handshake.',
            );
          }
          _maximumMessageBytes = (message['max_message_bytes'] as int).clamp(
            1,
            8 * 1024 * 1024,
          );
          _isOpen = true;
          if (!_opened.isCompleted) _opened.complete();
        } else {
          _onMessage(this, message);
        }
      } on Object catch (error) {
        _finish(error);
        return;
      }
    }
  }

  void _finish([Object? error]) {
    if (_closed) return;
    _closed = true;
    if (!_opened.isCompleted) {
      _opened.completeError(
        error ?? const SocketException('Relapse closed before channel setup.'),
      );
    }
    _socket.destroy();
    _onClosed(this, error);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    _socket.destroy();
  }
}
