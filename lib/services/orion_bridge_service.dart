import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/bridge_models.dart';

/// Original Orion v2 HTTP bridge. Construction never starts a server. Only the
/// primary desktop engine calls [start]; companion windows share its snapshot.
class OrionBridgeService extends ChangeNotifier {
  OrionBridgeService({
    Future<String> Function()? scriptLoader,
    this.macSploitMode = false,
    Iterable<int>? macSploitPorts,
    String nativeExecutorPreference = 'auto',
    int? nativePortPreference,
    this.nativeScanInterval = defaultNativeScanInterval,
    this.clientTimeout = const Duration(milliseconds: 3500),
    this.longPollTimeout = const Duration(seconds: 2),
    this.watchdogInterval = const Duration(milliseconds: 500),
    this.requestTimeout = const Duration(seconds: 5),
    this.maximumClients = 64,
    this.maximumQueuedPerClient = 128,
    this.maximumRememberedLogs = 500,
    this.maximumRememberedResults = 512,
    this.maximumLogLength = 8192,
    this.maximumScriptBytes = 2 * 1024 * 1024,
    this.maximumQueuedBytes = 32 * 1024 * 1024,
    this.maximumRequestBytes = 128 * 1024,
    Iterable<int>? opiumwarePorts,
    Iterable<int>? heliosPorts,
  }) : _heliosPorts = List.unmodifiable(
         heliosPorts ?? List.generate(10, (index) => 5553 + index),
       ),
       _macSploitPorts = List.unmodifiable(
         macSploitPorts ??
             List.generate(
               macSploitPortRangeEnd - macSploitPortRangeStart + 1,
               (index) => macSploitPortRangeStart + index,
             ),
       ),
       _opiumwarePorts = List.unmodifiable(
         opiumwarePorts ??
             List.generate(
               opiumwarePortRangeEnd - opiumwarePortRangeStart + 1,
               (index) => opiumwarePortRangeStart + index,
             ),
       ),
       _nativeExecutorPreference = nativeExecutorPreference,
       _nativePortPreference = nativePortPreference,
       _scriptLoader =
           scriptLoader ??
           (() => rootBundle.loadString('assets/bridge/Orion Bridge.lua'));
  static const protocolToken = 'orion-bridge-v2';
  static const defaultPort = 31337;
  static const macSploitPortRangeStart = 5553;
  static const macSploitPortRangeEnd = 5563;
  static const opiumwarePortRangeStart = 8392;
  static const opiumwarePortRangeEnd = 8397;
  static const macSploitDefaultPort = macSploitPortRangeStart;
  static const defaultNativeScanInterval = Duration(seconds: 5);
  static const macSploitConnectTimeout = Duration(seconds: 1);
  static const macSploitWriteTimeout = Duration(seconds: 5);
  final bool macSploitMode;
  final Duration nativeScanInterval;
  final List<int> _macSploitPorts;
  final List<int> _opiumwarePorts;
  final List<int> _heliosPorts;
  Timer? _macSploitScanner;
  String? _detectedNativeExecutor;
  String? get nativeExecutorName => _detectedNativeExecutor;
  String _nativeExecutorPreference;
  int? _nativePortPreference;
  String get nativeExecutorPreference => _nativeExecutorPreference;
  int? get nativePortPreference => _nativePortPreference;
  List<int> get availableNativePorts => switch (_nativeExecutorPreference) {
    'macsploit' => _macSploitPorts,
    'opiumware' => _opiumwarePorts,
    'helios' => _heliosPorts,
    _ => [..._macSploitPorts, ..._heliosPorts, ..._opiumwarePorts],
  };
  bool _isKnownNativePort(int port) =>
      _macSploitPorts.contains(port) ||
      _opiumwarePorts.contains(port) ||
      _heliosPorts.contains(port);

  void setNativeExecutorPreference(String preference) {
    if (!const {
          'auto',
          'macsploit',
          'opiumware',
          'helios',
        }.contains(preference) ||
        (preference == 'helios' && !Platform.isMacOS)) {
      throw ArgumentError.value(preference, 'preference');
    }
    if (_nativeExecutorPreference == preference) return;
    _nativeExecutorPreference = preference;
    if (_nativePortPreference != null &&
        !availableNativePorts.contains(_nativePortPreference)) {
      _nativePortPreference = null;
    }
    _detectedNativeExecutor = null;
    if (_macSploitRunning) _scanMacSploitPorts();
    _changed();
  }

  void setNativePortPreference(int? port) {
    if (port != null && !_isKnownNativePort(port)) {
      throw ArgumentError.value(port, 'port');
    }
    if (_nativePortPreference == port) return;
    _nativePortPreference = port;
    _detectedNativeExecutor = null;
    if (_macSploitRunning) _scanMacSploitPorts();
    _changed();
  }

  bool _macSploitRunning = false;
  bool _macSploitScanning = false;
  final Future<String> Function() _scriptLoader;
  final Duration clientTimeout;
  final Duration longPollTimeout;
  final Duration watchdogInterval;
  final Duration requestTimeout;
  final int maximumClients;
  final int maximumQueuedPerClient;
  final int maximumRememberedLogs;
  final int maximumRememberedResults;
  final int maximumLogLength;
  final int maximumScriptBytes;
  final int maximumQueuedBytes;
  final int maximumRequestBytes;
  final _sessions = <String, _Session>{};
  final _logs = Queue<BridgeLogEntry>();
  (_Session, String)? _lastLogOrigin;
  // A retried POST/GET result must be acknowledged without printing it again.
  // Session+execution keys also separate a broadcast's independent results.
  final _reportedResults = <(String, String)>{};
  final _connectedEvents = StreamController<BridgeClient>.broadcast(sync: true);
  final _logEvents = StreamController<BridgeLogEntry>.broadcast(sync: true);
  final _random = Random.secure();
  HttpServer? _server;
  Timer? _watchdog;
  Future<bool>? _starting;
  String? _error;
  bool _disposed = false;
  int _generation = 0;
  int _activeRequests = 0;
  int _queuedBytes = 0;
  String? _script;
  bool get listening => _server != null || _macSploitRunning;
  bool get usesMacSploit => macSploitMode;
  bool get usesNativeExecutor =>
      macSploitMode ||
      (Platform.isMacOS && _nativeExecutorPreference == 'helios');
  List<int> get macSploitPorts => List.unmodifiable(_macSploitPorts);
  List<int> get opiumwarePorts => List.unmodifiable(_opiumwarePorts);
  List<int> get heliosPorts => List.unmodifiable(_heliosPorts);
  bool get isConnected => _sessions.isNotEmpty;
  String? get error => _error;
  int get port =>
      _server?.port ?? (macSploitMode ? macSploitDefaultPort : defaultPort);
  List<BridgeClient> get clients {
    final result = _sessions.values.map(_client).toList();
    result.sort(
      (a, b) => _number(a.identifier).compareTo(_number(b.identifier)),
    );
    return List.unmodifiable(result);
  }

  List<BridgeLogEntry> get logs => List.unmodifiable(_logs);
  Stream<BridgeClient> get clientConnected => _connectedEvents.stream;
  Stream<BridgeLogEntry> get logReceived => _logEvents.stream;
  Future<bool> start({int port = defaultPort}) {
    if (_disposed) return Future.value(false);
    if (macSploitMode) return _startMacSploit();
    if (_server != null) return Future.value(true);
    return _starting ??= _bind(port).whenComplete(() => _starting = null);
  }

  Future<bool> _bind(int requestedPort) async {
    final generation = ++_generation;
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        requestedPort,
        shared: false,
      );
      if (_disposed || generation != _generation) {
        await server.close(force: true);
        return false;
      }
      server.idleTimeout = const Duration(seconds: 10);
      _server = server;
      _error = null;
      server.listen(
        (request) => unawaited(_handle(request)),
        onError: (Object error) {
          _error = 'Orion Bridge connection error: $error';
          _emit('error', _error!);
        },
      );
      _watchdog = Timer.periodic(watchdogInterval, (_) => _expire());
      _changed();
      return true;
    } on Object catch (error) {
      if (generation == _generation && !_disposed) {
        _error =
            'Orion Bridge could not listen on 127.0.0.1:$requestedPort: $error';
        _emit('error', _error!);
      }
      return false;
    }
  }

  BridgeExecutionReceipt enqueueExecute(
    String source, {
    Iterable<String>? targetIdentifiers,
  }) {
    final sourceBytes = utf8.encode(source).length;
    if (sourceBytes > maximumScriptBytes) {
      throw ArgumentError('Script exceeds the $maximumScriptBytes byte limit.');
    }
    _expire();
    if (macSploitMode) {
      throw StateError(
        'Use executeMacSploit for asynchronous MacSploit TCP execution.',
      );
    }
    final id =
        'exec_${List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final selected = targetIdentifiers?.map((id) => id.toLowerCase()).toSet();
    final targets = <String>[];
    final execution = _Execution(id, source, sourceBytes);
    for (final session in _sessions.values) {
      if (selected != null &&
          !selected.contains(session.identifier.toLowerCase())) {
        continue;
      }
      if (session.pending.length >= maximumQueuedPerClient ||
          _queuedBytes + sourceBytes > maximumQueuedBytes) {
        _emit(
          'warn',
          'Execution queue is full for ${session.identifier}.',
          session: session,
        );
        continue;
      }
      session.pending.add(execution);
      _queuedBytes += sourceBytes;
      targets.add(session.identifier);
      _wake(session);
    }
    if (targets.isNotEmpty) _changed();
    return BridgeExecutionReceipt(id: id, targets: targets);
  }

  bool disconnectClient(String identifier) {
    final matches = _sessions.values
        .where(
          (session) =>
              session.identifier.toLowerCase() == identifier.toLowerCase(),
        )
        .toList();
    for (final session in matches) {
      _remove(session);
    }
    if (matches.isNotEmpty) _changed();
    return matches.isNotEmpty;
  }

  void disconnectAll() {
    if (_sessions.isEmpty) return;
    for (final session in _sessions.values.toList()) {
      _remove(session);
    }
    _changed();
  }

  void clearLogs() {
    _logs.clear();
    _lastLogOrigin = null;
    _changed();
  }

  Future<void> close() async {
    final starting = _starting;
    ++_generation;
    _macSploitScanner?.cancel();
    _macSploitScanner = null;
    _macSploitRunning = false;
    _watchdog?.cancel();
    _watchdog = null;
    final server = _server;
    _server = null;
    for (final session in _sessions.values.toList()) {
      _remove(session);
    }
    _changed();
    await server?.close(force: true);
    // A cancelled bind may still hold its socket until its async continuation
    // runs. A caller awaiting close can immediately start a fresh listener.
    await starting;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(close());
    unawaited(_connectedEvents.close());
    unawaited(_logEvents.close());
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> _startMacSploit() async {
    if (_macSploitRunning) return true;
    _macSploitRunning = true;
    _error = null;
    _macSploitScanner = Timer.periodic(
      nativeScanInterval,
      (_) => _scanMacSploitPorts(),
    );
    _scanMacSploitPorts();
    _changed();
    return true;
  }

  Future<void> _scanMacSploitPorts() async {
    if (!_macSploitRunning || _disposed || _macSploitScanning) return;
    _macSploitScanning = true;
    _Session? activeSession;
    try {
      final candidates = _nativeProbeOrder().toList();
      for (
        var candidateIndex = 0;
        candidateIndex < candidates.length;
        candidateIndex++
      ) {
        if (!_macSploitRunning || _disposed) return;
        var (executor, port, index) = candidates[candidateIndex];
        if (executor == 'Helios') {
          final name = await _probeHelios(port);
          if (name != null) {
            activeSession = _nativeExecutorSession(port, index + 1, name);
            break;
          }
          if (_nativeExecutorPreference == 'helios' ||
              !_macSploitPorts.contains(port)) {
            continue;
          }
          // Probe MacSploit only after Helios has failed its identity check
          // on this overlapping port.
          if (candidateIndex + 1 >= candidates.length ||
              candidates[candidateIndex + 1].$1 != 'MacSploit' ||
              candidates[candidateIndex + 1].$2 != port) {
            continue;
          }
          candidateIndex++;
          (executor, port, index) = candidates[candidateIndex];
        }
        Socket? probe;
        try {
          probe = await Socket.connect(
            InternetAddress.loopbackIPv4,
            port,
            timeout: const Duration(milliseconds: 500),
          );
          activeSession = _nativeExecutorSession(
            port,
            index + 1,
            executor == 'MacSploit' ||
                    (_heliosPorts.contains(port) && executor != 'Helios')
                ? 'Unknown'
                : executor,
          );
          // A peer may reset its accepted probe socket as soon as it closes;
          // connection acceptance already confirms the executor is running.
          try {
            await probe.close();
          } on Object {
            probe.destroy();
          }
          break;
        } on Object {
          probe?.destroy();
        }
      }
      _detectedNativeExecutor = activeSession?.transport;
      _publishMacSploitClient(activeSession);
    } finally {
      _macSploitScanning = false;
    }
  }

  Iterable<(String, int, int)> _nativeProbeOrder() sync* {
    final selectedPort = _nativePortPreference;
    if (selectedPort != null) {
      final overlapsHelios = _heliosPorts.contains(selectedPort);
      final executor = _nativeExecutorPreference == 'helios'
          ? 'Helios'
          : _nativeExecutorPreference == 'auto' && overlapsHelios
          ? 'Helios'
          : _nativeExecutorPreference == 'opiumware' ||
                (_opiumwarePorts.contains(selectedPort) &&
                    !_macSploitPorts.contains(selectedPort) &&
                    !overlapsHelios)
          ? 'Opiumware'
          : 'MacSploit';
      final ports = switch (executor) {
        'MacSploit' => _macSploitPorts,
        'Opiumware' => _opiumwarePorts,
        _ => _heliosPorts,
      };
      if (availableNativePorts.contains(selectedPort)) {
        if (overlapsHelios && executor == 'MacSploit') {
          yield ('Helios', selectedPort, _heliosPorts.indexOf(selectedPort));
        }
        yield (executor, selectedPort, ports.indexOf(selectedPort));
      }
      return;
    }
    final preferredExecutor = _nativeExecutorPreference;
    final executors = switch (preferredExecutor) {
      'macsploit' => ['MacSploit'],
      'opiumware' => ['Opiumware'],
      'helios' => ['Helios'],
      _ =>
        Platform.isMacOS
            ? ['Helios', 'MacSploit', 'Opiumware']
            : ['MacSploit', 'Opiumware'],
    };
    for (final executor in executors) {
      final ports = switch (executor) {
        'MacSploit' => _macSploitPorts,
        'Opiumware' => _opiumwarePorts,
        _ => _heliosPorts,
      };
      for (var index = 0; index < ports.length; index++) {
        yield (executor, ports[index], index);
      }
    }
  }

  _Session _macSploitSession(int port, int number) =>
      _nativeExecutorSession(port, number, 'MacSploit');

  _Session _nativeExecutorSession(int port, int number, String executor) =>
      _Session(
        executor == 'MacSploit' || executor == 'Unknown'
            ? _macSploitSessionId(port)
            : executor == 'Helios' || executor == 'Helios Mac'
            ? 'helios:$port'
            : 'opiumware:$port',
        'User$number',
        'User$number',
        executor,
        executor,
        executor,
        '',
      );

  void _publishMacSploitClient(_Session? activeSession) {
    final previousId = _sessions.keys.firstOrNull;
    _sessions
      ..clear()
      ..addEntries([
        if (activeSession != null) MapEntry(activeSession.id, activeSession),
      ]);
    _error = null;
    if (previousId != activeSession?.id) {
      _changed();
      if (activeSession != null && !_disposed) {
        _connectedEvents.add(_client(activeSession));
      }
    }
  }

  /// Checks the configured localhost ports in ascending order, matching the
  /// executor status probe exposed by the native MacSploit bridge API.
  Future<bool> isMacSploitRunning() async {
    if (_nativeExecutorPreference == 'opiumware' ||
        _nativeExecutorPreference == 'helios' ||
        (_nativePortPreference != null &&
            !_macSploitPorts.contains(_nativePortPreference))) {
      return false;
    }
    final selectedPort = _nativePortPreference;
    final ports = selectedPort == null
        ? _macSploitPorts
        : _macSploitPorts.where((port) => port == selectedPort);
    for (final port in ports) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 500),
        );
        // Match the native status probe: TCP acceptance is sufficient. Some
        // executor builds reset the connection during immediate teardown.
        try {
          await socket.close();
        } on Object {
          socket.destroy();
        }
        return true;
      } on Object {
        socket?.destroy();
      }
    }
    return false;
  }

  /// Execute using the first responsive localhost instance, probing ports in
  /// ascending order and closing each connection after its write is flushed.
  /// MacSploit execution is single-target; the legacy selection argument is
  /// accepted for API compatibility but does not alter first-available choice.
  Future<BridgeExecutionReceipt> executeNativeExecutor(
    String source, {
    Iterable<String>? targetIdentifiers,
  }) async {
    final executor = await detectNativeExecutor();
    return switch (executor) {
      'MacSploit' => executeMacSploit(
        source,
        targetIdentifiers: targetIdentifiers,
        port: _nativePortPreference,
      ),
      'Opiumware' => executeOpiumware(
        source,
        targetIdentifiers: targetIdentifiers,
        port: _nativePortPreference,
      ),
      'Helios' ||
      'Helios Mac' => executeHelios(source, port: _nativePortPreference),
      _ => throw StateError(
        'No executor detected. Start Helios (5553–5562), MacSploit (5553–5563), or Opiumware (8392–8397).',
      ),
    };
  }

  Future<String?> detectNativeExecutor() async {
    final candidates = _nativeProbeOrder().toList();
    for (
      var candidateIndex = 0;
      candidateIndex < candidates.length;
      candidateIndex++
    ) {
      final (executor, port, index) = candidates[candidateIndex];
      if (executor == 'Helios') {
        try {
          final executorName = await _probeHelios(port);
          if (executorName != null) {
            _detectedNativeExecutor = executorName;
            _publishMacSploitClient(
              _nativeExecutorSession(port, index + 1, executorName),
            );
            return executorName;
          }
        } on Object {
          // Fall through to the legacy TCP protocol when this port is shared.
        }
        if (_nativeExecutorPreference == 'helios') continue;
        if (!_macSploitPorts.contains(port)) continue;
      }
      Socket? socket;
      try {
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 500),
        );
        try {
          await socket.close();
        } on Object {
          socket.destroy();
        }
        // MacSploit's native TCP ports overlap Helios. A TCP accept cannot
        // positively identify which executor owns the port, so do not report
        // MacSploit without its executor name from the Lua bridge.
        if (executor == 'MacSploit' && _heliosPorts.contains(port)) {
          // TCP success isn't enough to classify the shared Helios port.
          final identifiedName = _probeLuaExecutorName();
          if (identifiedName != null &&
              identifiedName.toLowerCase().contains('macsploit')) {
            _detectedNativeExecutor = identifiedName;
            _publishMacSploitClient(
              _nativeExecutorSession(port, index + 1, identifiedName),
            );
            return identifiedName;
          }
          _detectedNativeExecutor = 'Unknown';
          _publishMacSploitClient(
            _nativeExecutorSession(port, index + 1, 'Unknown'),
          );
          return 'Unknown';
        }
        _detectedNativeExecutor = executor;
        _publishMacSploitClient(
          _nativeExecutorSession(port, index + 1, executor),
        );
        return executor;
      } on Object {
        socket?.destroy();
      }
    }
    _detectedNativeExecutor = null;
    return null;
  }

  String? _probeLuaExecutorName() {
    final name = _sessions.values
        .map((session) => session.executorName.trim())
        .where((value) => value.isNotEmpty && value != 'Unknown')
        .firstOrNull;
    return name;
  }

  Future<String?> _probeHelios(int port) async {
    WebSocket? websocket;
    try {
      websocket = await WebSocket.connect(
        'ws://127.0.0.1:$port',
      ).timeout(const Duration(milliseconds: 500));
      return await _identifyHeliosExecutor(websocket);
    } on Object {
      websocket?.close();
      return null;
    } finally {
      websocket?.close();
    }
  }

  Future<String?> _identifyHeliosExecutor(WebSocket socket) async {
    try {
      final message = await socket
          .timeout(const Duration(milliseconds: 250))
          .first;
      if (message is! String) return null;
      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic> || decoded['op'] != 'status') {
        return null;
      }
      final name = decoded['name'];
      if (name is! String || !name.toLowerCase().contains('helios')) {
        return null;
      }
      final cleanedName = name.trim();
      return cleanedName.toLowerCase().contains('mac')
          ? 'Helios Mac'
          : 'Helios';
    } on Object {
      // On shared ports, require an explicit Helios status frame. A successful
      // WebSocket upgrade alone is not enough to distinguish executors.
      return null;
    }
  }

  Future<BridgeExecutionReceipt> executeHelios(
    String source, {
    int? port,
  }) async {
    final bytes = utf8.encode(source);
    if (bytes.length > maximumScriptBytes) {
      throw ArgumentError('Script exceeds the $maximumScriptBytes byte limit.');
    }
    final ports = port == null
        ? _heliosPorts
        : _heliosPorts.where((candidate) => candidate == port);
    for (final candidatePort in ports) {
      WebSocket? socket;
      try {
        socket = await WebSocket.connect(
          'ws://127.0.0.1:$candidatePort',
        ).timeout(const Duration(milliseconds: 500));
        socket.add(jsonEncode({'op': 'execute', 'id': 1, 'script': source}));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await socket.close().timeout(const Duration(milliseconds: 500));
        final number = _heliosPorts.indexOf(candidatePort) + 1;
        final executorName = await _probeHelios(candidatePort) ?? 'Helios';
        _detectedNativeExecutor = executorName;
        _publishMacSploitClient(
          _nativeExecutorSession(candidatePort, number, executorName),
        );
        return BridgeExecutionReceipt(
          id: 'helios_${DateTime.now().microsecondsSinceEpoch}',
          targets: ['User$number'],
        );
      } on Object {
        socket?.close();
      }
    }
    _publishMacSploitClient(null);
    _detectedNativeExecutor = null;
    throw StateError(
      'Helios: no WebSocket instance found on ${port ?? 'ports 5553–5562'}.',
    );
  }

  Future<bool> isOpiumwareRunning() async {
    if (_nativeExecutorPreference == 'macsploit' ||
        (_nativePortPreference != null &&
            !_opiumwarePorts.contains(_nativePortPreference))) {
      return false;
    }
    final selectedPort = _nativePortPreference;
    return _hasResponsivePort(
      selectedPort == null
          ? _opiumwarePorts
          : _opiumwarePorts.where((port) => port == selectedPort),
    );
  }

  Future<bool> _hasResponsivePort(Iterable<int> ports) async {
    for (final port in ports) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 500),
        );
        try {
          await socket.close();
        } on Object {
          socket.destroy();
        }
        return true;
      } on Object {
        socket?.destroy();
      }
    }
    return false;
  }

  Future<BridgeExecutionReceipt> executeMacSploit(
    String source, {
    Iterable<String>? targetIdentifiers,
    int? port,
  }) async {
    final encodedSource = utf8.encode(source);
    if (encodedSource.length > maximumScriptBytes) {
      throw ArgumentError('Script exceeds the $maximumScriptBytes byte limit.');
    }
    final ports = port == null
        ? _macSploitPorts
        : _macSploitPorts.where((candidate) => candidate == port).toList();
    for (final port in ports) {
      final userNumber = _macSploitPorts.indexOf(port) + 1;
      Socket socket;
      try {
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: macSploitConnectTimeout,
        );
      } on Object {
        continue;
      }

      try {
        socket.add(_macSploitExecuteFrame(encodedSource));
        await socket.flush().timeout(macSploitWriteTimeout);
      } on Object {
        socket.destroy();
        continue;
      }

      // Once flush succeeds, the full frame has been handed to the TCP stack.
      // MacSploit may reset the connection as it closes its accepted socket;
      // that teardown must not turn a successful write into a second execute
      // attempt on another instance.
      try {
        await socket.close();
      } on Object {
        socket.destroy();
      }
      final identifier = 'User$userNumber';
      _detectedNativeExecutor = 'MacSploit';
      _publishMacSploitClient(_macSploitSession(port, userNumber));
      return BridgeExecutionReceipt(
        id: 'macsploit_${DateTime.now().microsecondsSinceEpoch}',
        targets: [identifier],
      );
    }
    _publishMacSploitClient(null);
    throw StateError(
      'MacSploit: no instance found on ${port ?? 'ports 5553–5563'}.',
    );
  }

  Future<BridgeExecutionReceipt> executeOpiumware(
    String source, {
    Iterable<String>? targetIdentifiers,
    int? port,
  }) async {
    final payload = utf8.encode('OpiumwareScript $source');
    final compressed = ZLibCodec(level: 6).encode(payload);
    final ports = port == null
        ? _opiumwarePorts
        : _opiumwarePorts.where((candidate) => candidate == port).toList();
    for (final port in ports) {
      final userNumber = _opiumwarePorts.indexOf(port) + 1;
      Socket socket;
      try {
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: macSploitConnectTimeout,
        );
      } on Object {
        continue;
      }
      try {
        socket.add(compressed);
        await socket.flush().timeout(macSploitWriteTimeout);
      } on Object {
        socket.destroy();
        continue;
      }
      try {
        await socket.close();
      } on Object {
        socket.destroy();
      }
      final identifier = 'User$userNumber';
      _detectedNativeExecutor = 'Opiumware';
      _publishMacSploitClient(
        _nativeExecutorSession(port, userNumber, 'Opiumware'),
      );
      return BridgeExecutionReceipt(
        id: 'opiumware_${DateTime.now().microsecondsSinceEpoch}',
        targets: [identifier],
      );
    }
    _publishMacSploitClient(null);
    _detectedNativeExecutor = null;
    throw StateError(
      'Opiumware: no instance found on ${port ?? 'ports 8392–8397'}.',
    );
  }

  /// Encodes the supplied 16-byte MacSploit TCP header and NUL-terminated Lua.
  static Uint8List _macSploitExecuteFrame(List<int> source) {
    final payloadSize = source.length + 1;
    final frame = Uint8List(16 + payloadSize);
    ByteData.sublistView(frame).setUint32(8, payloadSize, Endian.little);
    frame.setRange(16, 16 + source.length, source);
    frame[frame.length - 1] = 0;
    return frame;
  }

  String _macSploitSessionId(int port) => 'macsploit:$port';

  void _expire() {
    final now = DateTime.now().toUtc();
    final expired = _sessions.values
        .where((session) => now.difference(session.lastSeenUtc) > clientTimeout)
        .toList();
    for (final session in expired) {
      _remove(session);
    }
    if (expired.isNotEmpty) _changed();
  }

  void _remove(_Session session) {
    _sessions.remove(session.id);
    for (final item in session.pending) {
      _queuedBytes -= item.byteLength;
    }
    session.pending.clear();
    _wake(session);
  }

  void _wake(_Session session) {
    for (final waiter in session.waiters.toList()) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  void _emit(
    String level,
    String message, {
    _Session? session,
    String? executionId,
  }) {
    if (_disposed) return;
    final normalized = level.trim().toLowerCase();
    final entry = BridgeLogEntry(
      timestampUtc: DateTime.now().toUtc(),
      level: normalized.isEmpty ? 'info' : _bounded(normalized, 32),
      message: _bounded(message, maximumLogLength),
      identifier: session?.identifier,
      executionId: executionId,
    );
    _logs.add(entry);
    _lastLogOrigin = session == null
        ? null
        : (session, session.bridgeGeneration);
    while (_logs.length > maximumRememberedLogs) {
      _logs.removeFirst();
    }
    _logEvents.add(entry);
    _changed();
  }

  Future<void> _handle(HttpRequest request) async {
    _activeRequests++;
    final generation = _generation;
    try {
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.headers.set('X-Content-Type-Options', 'nosniff');
      // The compatibility token identifies a protocol; it is not a secret.
      // Reject browser origins/fetches and unexpected hosts as well as binding
      // only to loopback, so websites/other machines cannot drive this bridge.
      final host = request.headers.host?.toLowerCase();
      final fetchSite = request.headers.value('sec-fetch-site');
      if (request.headers.value('origin') != null ||
          (fetchSite != null && fetchSite != 'none') ||
          (host != '127.0.0.1' && host != 'localhost')) {
        await _json(request, 403, {'error': 'local bridge requests only'});
        return;
      }
      if (_activeRequests > 256) {
        await _json(request, 503, {'error': 'too many bridge requests'});
        return;
      }
      if (request.uri.toString().length > maximumRequestBytes ||
          request.contentLength > maximumRequestBytes) {
        await _json(request, 413, {'error': 'request too large'});
        return;
      }
      if (request.method != 'GET' && request.method != 'POST') {
        request.response.headers.set(HttpHeaders.allowHeader, 'GET, POST');
        await _json(request, 405, {'error': 'method not allowed'});
        return;
      }
      final path = request.uri.path
          .replaceFirst(RegExp(r'/+$'), '')
          .toLowerCase();
      if (const {
        '/bridge.lua',
        '/port_bridge.lua',
        '/stream_bridge.lua',
        '/compat_bridge.lua',
      }.contains(path)) {
        if (request.method != 'GET') {
          await _json(request, 405, {'error': 'method not allowed'});
          return;
        }
        try {
          _script ??= await _scriptLoader();
          await _text(request, 200, _script!, 'text/plain; charset=utf-8');
        } on Object {
          await _text(
            request,
            404,
            '-- Orion Bridge.lua is not installed.\n',
            'text/plain; charset=utf-8',
          );
        }
        return;
      }
      if (path == '/status') {
        _expire();
        await _json(request, 200, {
          'connected': isConnected,
          'port_connected': _sessions.values.any((s) => s.transport == 'port'),
          'stream_connected': _sessions.values.any(
            (s) => s.transport == 'stream',
          ),
          'compat_connected': _sessions.values.any(
            (s) => s.transport == 'compat',
          ),
          'queued': _sessions.values.fold<int>(
            0,
            (sum, s) => sum + s.pending.length,
          ),
          'clients': clients
              .map(
                (client) => {
                  'identifier': client.identifier,
                  'username': client.username,
                  'transport': client.transport,
                  'executorName': client.executorName,
                },
              )
              .toList(),
        });
        return;
      }
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.length != 2 ||
          !const {
            'port_bridge',
            'stream_bridge',
            'compat_bridge',
          }.contains(segments[0])) {
        await _json(request, 404, {'error': 'not found'});
        return;
      }
      final supplied =
          request.uri.queryParameters['protocol'] ??
          request.headers.value('X-Orion-Bridge-Protocol');
      if (supplied != protocolToken) {
        await _json(request, 403, {'error': 'invalid bridge protocol'});
        return;
      }
      final transport = segments[0].split('_').first;
      final endpoint = segments[1];
      if (!const {
        'hello',
        'ping',
        'next',
        'result',
        'log',
      }.contains(endpoint)) {
        await _json(request, 404, {'error': 'unknown bridge endpoint'});
        return;
      }
      _expire();
      final suppliedId = request.uri.queryParameters['session_id']?.trim();
      final sessionId = suppliedId == null || suppliedId.isEmpty
          ? 'legacy-$transport'
          : suppliedId;
      if (!_validSessionId(sessionId)) {
        await _json(request, 400, {'error': 'invalid session id'});
        return;
      }
      if (endpoint == 'hello') {
        await _hello(request, transport, sessionId, generation);
        return;
      }
      final session = _sessions[sessionId];
      if (session == null || session.transport != transport) {
        await _json(request, 409, {'error': 'bridge hello required'});
        return;
      }
      _requireGeneration(
        session,
        request.uri.queryParameters['bridge_generation'],
      );
      session.lastSeenUtc = DateTime.now().toUtc();
      if (endpoint == 'ping') {
        await _json(request, 200, {'ok': true});
      } else if (endpoint == 'next') {
        await _next(request, session, transport);
      } else {
        final values = await _values(request);
        if (!identical(_sessions[session.id], session) ||
            session.transport != transport) {
          await _json(request, 409, {'error': 'bridge hello required'});
          return;
        }
        _requireGeneration(session, values['bridge_generation']);
        session.lastSeenUtc = DateTime.now().toUtc();
        if (endpoint == 'log') {
          _emit(
            values['level'] ?? 'info',
            _decodeValue(values, 'message', 'invalid encoded log'),
            session: session,
          );
        } else {
          final suppliedId = values['id'];
          final id = _bounded(suppliedId ?? 'unknown', 128);
          // Stable execution IDs allow the Lua outbox to retry after a lost
          // HTTP response. Successful results are transport acknowledgements;
          // the client's mirrored print/warn/error stream is the console output.
          // Missing IDs retain the legacy failure-reporting behavior.
          final remembered = suppliedId != null && suppliedId.isNotEmpty;
          final firstResult =
              !remembered || _reportedResults.add((session.id, id));
          if (firstResult) {
            while (_reportedResults.length > maximumRememberedResults) {
              _reportedResults.remove(_reportedResults.first);
            }
            final succeeded = values['ok']?.trim().toLowerCase() == 'true';
            if (!succeeded) {
              final failure = _decodeValue(
                values,
                'error',
                'invalid encoded error',
              );
              final previous = _logs.isEmpty ? null : _logs.last;
              final alreadyMirrored =
                  previous != null &&
                  identical(_lastLogOrigin?.$1, session) &&
                  _lastLogOrigin?.$2 == session.bridgeGeneration &&
                  previous.identifier == session.identifier &&
                  previous.executionId == null &&
                  previous.level == 'error' &&
                  previous.message == failure &&
                  DateTime.now().toUtc().difference(previous.timestampUtc) <=
                      const Duration(seconds: 2);
              if (!alreadyMirrored) {
                _emit(
                  'error',
                  'Execution failed: ${failure.isEmpty ? 'unknown error' : failure}',
                  session: session,
                  executionId: id,
                );
              }
            }
          }
        }
        await _json(request, 200, {'ok': true});
      }
    } on _RequestFailure catch (error) {
      await _errorResponse(request, error.status, error.message);
    } on FormatException {
      await _errorResponse(request, 400, 'invalid request values');
    } on TimeoutException {
      await _errorResponse(request, 408, 'request timed out');
    } on Object catch (error) {
      if (_server != null &&
          !_disposed &&
          error is! SocketException &&
          error is! HttpException) {
        _emit('error', 'Orion Bridge request failed: $error');
      }
      try {
        await _json(request, 500, {'error': 'bridge request failed'});
      } on Object {
        /* peer abandoned long poll */
      }
    } finally {
      _activeRequests--;
      try {
        await request.response.close();
      } on Object {
        /* peer closed */
      }
    }
  }

  Future<void> _hello(
    HttpRequest request,
    String transport,
    String fallbackId,
    int generation,
  ) async {
    final values = await _values(request);
    if (_server == null || generation != _generation) {
      throw const _RequestFailure(503, 'bridge stopped');
    }
    final supplied = values['session_id']?.trim();
    final id = supplied == null || supplied.isEmpty ? fallbackId : supplied;
    if (!_validSessionId(id)) {
      throw const _RequestFailure(400, 'invalid session id');
    }
    final clientLabel = _clean(values['client'], '$transport-bridge', 64);
    final displayName = _clean(values['display_name'], '', 64);
    final username = displayName.isEmpty
        ? _clean(values['username'], clientLabel, 64)
        : displayName;
    // Legacy clients know only their transport label. Never present that
    // label as an executor, and keep known metadata on older hello refreshes.
    final executorName = values.containsKey('executor_name')
        ? _clean(values['executor_name'], '', 64)
        : null;
    final requested = _identifier(values['requested_identifier']);
    final bridgeGeneration = _generationTag(values['bridge_generation']) ?? '';
    var session = _sessions[id];
    final newClient = session == null;
    if (session == null) {
      if (_sessions.length >= maximumClients) {
        throw const _RequestFailure(429, 'client limit reached');
      }
      final used = _sessions.values
          .map((s) => s.identifier.toLowerCase())
          .toSet();
      var assigned = requested;
      if (used.contains(assigned.toLowerCase())) {
        var number = 1;
        while (used.contains('user$number')) {
          number++;
        }
        assigned = 'User$number';
      }
      session = _Session(
        id,
        assigned,
        username,
        transport,
        clientLabel,
        executorName ?? '',
        bridgeGeneration,
      );
      _sessions[id] = session;
    } else {
      final previousNumber = BigInt.tryParse(session.bridgeGeneration);
      final requestedNumber = BigInt.tryParse(bridgeGeneration);
      if (bridgeGeneration.isNotEmpty &&
          previousNumber != null &&
          requestedNumber != null &&
          requestedNumber < previousNumber) {
        throw const _RequestFailure(409, 'stale bridge generation');
      }
      // Replacing the Lua bridge leaves its old HTTP poll alive until it
      // returns. Revoke that poll before it can consume work for the new
      // generation. Periodic and older hellos keep the same queue and epoch.
      if (session.transport != transport ||
          (bridgeGeneration.isNotEmpty &&
              bridgeGeneration != session.bridgeGeneration)) {
        session.pollEpoch++;
        _wake(session);
      }
      if (bridgeGeneration.isNotEmpty) {
        session.bridgeGeneration = bridgeGeneration;
      }
      session.username = username;
      session.transport = transport;
      session.clientLabel = clientLabel;
      if (executorName != null) session.executorName = executorName;
      session.lastSeenUtc = DateTime.now().toUtc();
    }
    _changed();
    if (newClient && !_disposed) _connectedEvents.add(_client(session));
    await _json(request, 200, {
      'ok': true,
      'transport': transport,
      'identifier': session.identifier,
      'username': session.username,
      'executorName': session.executorName,
      'reassigned': session.identifier.toLowerCase() != requested.toLowerCase(),
    });
  }

  Future<void> _next(
    HttpRequest request,
    _Session session,
    String transport,
  ) async {
    final pollEpoch = session.pollEpoch;
    if (session.waiters.length >= 2) {
      throw const _RequestFailure(429, 'too many pending polls');
    }
    if (session.pending.isEmpty) {
      final waiter = Completer<void>();
      session.waiters.add(waiter);
      try {
        await waiter.future.timeout(longPollTimeout, onTimeout: () {});
      } finally {
        session.waiters.remove(waiter);
      }
    }
    if (!identical(_sessions[session.id], session) ||
        session.transport != transport ||
        session.pollEpoch != pollEpoch) {
      await _json(request, 409, {'error': 'bridge hello required'});
      return;
    }
    // Successful long polls are heartbeats too, avoiding scheduler jitter at
    // the short v2 disconnect threshold while the client is still connected.
    session.lastSeenUtc = DateTime.now().toUtc();
    final batch = <Map<String, String>>[];
    while (session.pending.isNotEmpty && batch.length < 8) {
      final item = session.pending.removeFirst();
      _queuedBytes -= item.byteLength;
      batch.add({
        'id': item.id,
        'source_b64': base64.encode(utf8.encode(item.source)),
        'encoding': 'base64',
        'origin': 'editor',
      });
    }
    if (batch.isNotEmpty) _changed();
    await _json(
      request,
      200,
      batch.isEmpty
          ? {'exec': null}
          : batch.length == 1
          ? {'exec': batch.first}
          : {'execs': batch},
    );
  }

  Future<Map<String, String>> _values(HttpRequest request) async {
    final result = <String, String>{};
    for (final entry in request.uri.queryParameters.entries) {
      result[entry.key.toLowerCase()] = entry.value;
    }
    if (request.method != 'POST') return result;
    if (request.contentLength > maximumRequestBytes) {
      throw const _RequestFailure(413, 'request too large');
    }
    final bytes = BytesBuilder(copy: false);
    final iterator = StreamIterator<List<int>>(request);
    final elapsed = Stopwatch()..start();
    try {
      while (true) {
        final remaining = requestTimeout - elapsed.elapsed;
        if (remaining <= Duration.zero) {
          throw TimeoutException('bridge request body timed out');
        }
        if (!await iterator.moveNext().timeout(remaining)) break;
        final chunk = iterator.current;
        if (bytes.length + chunk.length > maximumRequestBytes) {
          throw const _RequestFailure(413, 'request too large');
        }
        bytes.add(chunk);
      }
    } on _RequestFailure catch (error) {
      // Cancelling an unread HTTP body can close its socket on Windows. Send
      // the bounded error response before cancellation so clients receive 413
      // and know to reconnect instead of seeing an interrupted header.
      request.response.persistentConnection = false;
      await _errorResponse(request, error.status, error.message);
      await request.response.close();
      rethrow;
    } finally {
      await iterator.cancel();
    }
    final body = utf8.decode(bytes.takeBytes()).trim();
    if (body.isEmpty) return result;
    if (body.startsWith('{') ||
        request.headers.contentType?.mimeType == 'application/json') {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const _RequestFailure(400, 'expected a JSON object');
      }
      for (final entry in decoded.entries) {
        if (entry.value is Map || entry.value is List) {
          throw const _RequestFailure(400, 'expected scalar values');
        }
        result[entry.key.toLowerCase()] = entry.value?.toString() ?? '';
      }
    } else {
      for (final entry in Uri.splitQueryString(body).entries) {
        result[entry.key.toLowerCase()] = entry.value;
      }
    }
    return result;
  }

  String _decodeValue(Map<String, String> values, String key, String fallback) {
    final plain = values[key];
    if (plain != null && plain.trim().isNotEmpty) {
      return _bounded(plain, maximumLogLength);
    }
    final encoded = values['${key}_b64'];
    if (encoded == null || encoded.isEmpty) return plain ?? '';
    try {
      return _bounded(utf8.decode(base64.decode(encoded)), maximumLogLength);
    } on FormatException {
      return fallback;
    }
  }

  Future<void> _errorResponse(
    HttpRequest request,
    int status,
    String message,
  ) async {
    try {
      await _json(request, status, {'error': message});
    } on Object {
      // A partial or cancelled request can already have closed its socket.
    }
  }

  Future<void> _json(HttpRequest request, int status, Object payload) => _text(
    request,
    status,
    jsonEncode(payload),
    'application/json; charset=utf-8',
  );
  Future<void> _text(
    HttpRequest request,
    int status,
    String value,
    String type,
  ) async {
    final response = request.response;
    response.statusCode = status;
    response.headers.set(HttpHeaders.contentTypeHeader, type);
    final bytes = utf8.encode(value);
    response.contentLength = bytes.length;
    response.add(bytes);
  }

  BridgeClient _client(_Session session) => BridgeClient(
    identifier: session.identifier,
    username: session.username,
    transport: session.transport,
    clientLabel: session.clientLabel,
    executorName: session.executorName,
    sessionId: session.id,
    pendingCount: session.pending.length,
  );
  void _requireGeneration(_Session session, String? supplied) {
    final generation = _generationTag(supplied);
    // Untagged legacy sessions remain fully compatible. Once upgraded, an
    // untagged request can belong to the old bridge still finishing an HTTP
    // call, so it must not consume or report work for the new generation.
    if (generation == null && session.bridgeGeneration.isEmpty) return;
    if (generation != session.bridgeGeneration) {
      throw const _RequestFailure(409, 'bridge hello required');
    }
  }

  static String? _generationTag(String? supplied) {
    if (supplied == null) return null;
    final tag = supplied.trim();
    if (!RegExp(r'^[A-Za-z0-9_.:-]{1,64}$').hasMatch(tag)) {
      throw const _RequestFailure(400, 'invalid bridge generation');
    }
    if (RegExp(r'^[0-9]+$').hasMatch(tag)) {
      return BigInt.parse(tag).toString();
    }
    return tag;
  }

  static String _bounded(String value, int length) =>
      value.length <= length ? value : value.substring(0, length);
  static String _clean(String? value, String fallback, int length) {
    final cleaned =
        value?.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim() ?? '';
    return _bounded(cleaned.isEmpty ? fallback : cleaned, length);
  }

  static bool _validSessionId(String id) =>
      id.length <= 128 && !RegExp(r'[\x00-\x20\x7f]').hasMatch(id);
  static String _identifier(String? value) {
    final match = RegExp(
      r'^User([0-9]{1,9})$',
      caseSensitive: false,
    ).firstMatch(value?.trim() ?? '');
    final number = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
    return number > 0 ? 'User$number' : 'User1';
  }

  static int _number(String value) => int.tryParse(value.substring(4)) ?? 0;
}

class _Execution {
  const _Execution(this.id, this.source, this.byteLength);
  final String id;
  final String source;
  final int byteLength;
}

class _Session {
  _Session(
    this.id,
    this.identifier,
    this.username,
    this.transport,
    this.clientLabel,
    this.executorName,
    this.bridgeGeneration,
  ) : lastSeenUtc = DateTime.now().toUtc();
  final String id;
  final String identifier;
  String username;
  String transport;
  String clientLabel;
  String executorName;
  String bridgeGeneration;
  int pollEpoch = 0;
  DateTime lastSeenUtc;
  final pending = Queue<_Execution>();
  final waiters = <Completer<void>>[];
}

class _RequestFailure implements Exception {
  const _RequestFailure(this.status, this.message);
  final int status;
  final String message;
}
