import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/bridge_models.dart';

/// Where the RelapseGtk UI bridge is, using the same states as its
/// `OutputState` enum so Orion reports what RelapseGtk reports.
enum RelapseOutputState { off, waiting, connecting, active, failed }

/// Client for RelapseGtk's local protocol.
///
/// This mirrors RelapseGtk's own implementation (src/socket/client.c,
/// bridge.c, transport.c) rather than inventing a parallel design:
///
///  * one `@main` executor channel per socket, which answers `hello`/`status`,
///    `exec_result`, `log` and `error`;
///  * one `relapsegtk.session.v2` UI channel per game session. RelapseGtk runs
///    `session.luau` on `@main`, then connects the channel and configures it
///    with `{"op":"configure","version":2,"redirect":<bool>}`;
///  * scripts are only submitted once that UI channel has acknowledged the
///    configuration, wrapped in `getgenv().__relapsegtk_session_v2.execute`
///    so the script runs inside the live game session and its output comes
///    back over the same channel.
///
/// Relapse serialises Lua numbers as JSON doubles, so every integer field it
/// sends can arrive as `2.0` rather than `2`. RelapseGtk accepts integral
/// doubles; so does this client.
class RelapseGtkService extends ChangeNotifier {
  RelapseGtkService({
    this.socketPath = defaultSocketPath,
    this.reconnectInterval = const Duration(seconds: 1),
    this.handshakeTimeout = const Duration(seconds: 10),
    this.handshakeRetry = const Duration(milliseconds: 250),
    this.maximumScriptBytes = 2 * 1024 * 1024,
    bool? manageProfiles,
    this.profileDirectory = '/tmp',
    String profileIdentifier = 'Relapse',
    Future<String> Function()? sessionScriptLoader,
    bool outputEnabled = true,
  }) : _managesProfiles = manageProfiles ?? socketPath == defaultSocketPath,
       _profileIdentifier = profileIdentifier,
       _outputEnabled = outputEnabled,
       _sessionScriptLoader =
           sessionScriptLoader ??
           (() => rootBundle.loadString('assets/relapsegtk/session.luau'));

  static const defaultSocketPath = '/tmp/relapse.sock';
  static const mainChannel = '@main';
  static const sessionChannel = 'relapsegtk.session.v2';
  static const protocolVersion = 1;
  static const sessionVersion = 2;
  static const sessionScriptName = 'relapsegtk-session.luau';
  static const executeScriptName = 'relapsegtk-execute.luau';
  static const maximumOutputEntries = 32;
  static const maximumOutputTextBytes = 4096;
  static const maximumProfileNameLength = 64;
  static const maximumSocketPaths = 128;
  static const maximumSocketPathBytes = 107;

  String socketPath;
  final Duration reconnectInterval;
  final Duration handshakeTimeout;
  final Duration handshakeRetry;
  final int maximumScriptBytes;
  final String profileDirectory;
  final bool _managesProfiles;
  final String _profileIdentifier;
  final Future<String> Function() _sessionScriptLoader;
  final Map<String, RelapseGtkService> _profileServices = {};
  final Map<String, StreamSubscription<BridgeLogEntry>> _profileLogs = {};
  final List<String> _socketPaths = [defaultSocketPath];
  final _logs = StreamController<BridgeLogEntry>.broadcast(sync: true);
  static Future<int>? _uidFuture;

  _RelapseChannel? _main;
  _RelapseChannel? _bridgeChannel;
  Timer? _reconnectTimer;
  Timer? _bridgeTimer;
  Timer? _discoveryTimer;
  DateTime? _bridgeDeadline;
  bool _enabled = false;
  bool _disposed = false;
  bool _connecting = false;
  bool _bridgeConnecting = false;
  bool _helloReceived = false;
  bool _connected = false;
  bool _ready = false;
  bool _bridgeConfigured = false;
  bool _outputEnabled = false;
  bool _discovering = false;
  RelapseOutputState _outputState = RelapseOutputState.off;
  String? _outputDetail;
  String? _error;
  int? _session;
  int _nextScriptId = 1;
  int _bridgeSession = 0;
  final Set<int> _bridgeScriptIds = {};
  final Map<int, String> _scriptNames = {};

  Stream<BridgeLogEntry> get logReceived => _logs.stream;
  List<String> get socketPaths => List.unmodifiable(_socketPaths);
  List<String> get connectedSocketPaths => _managesProfiles
      ? _profileServices.entries
            .where((entry) => entry.value.isConnected)
            .map((entry) => entry.key)
            .toList(growable: false)
      : (_connected ? [socketPath] : const []);
  List<String> get readySocketPaths => _managesProfiles
      ? _profileServices.entries
            .where((entry) => entry.value.isReady)
            .map((entry) => entry.key)
            .toList(growable: false)
      : (_connected && _ready ? [socketPath] : const []);

  /// Profiles whose UI channel has acknowledged its configuration. RelapseGtk
  /// only offers Execute in this state (`sessions_can_execute`), and so does
  /// Orion: submitting before the wrapper exists would run unwrapped code.
  List<String> get executableSocketPaths => _managesProfiles
      ? _profileServices.entries
            .where((entry) => entry.value.canExecute)
            .map((entry) => entry.key)
            .toList(growable: false)
      : (canExecute ? [socketPath] : const []);

  bool get enabled => _enabled;
  bool get isConnected =>
      _managesProfiles ? connectedSocketPaths.isNotEmpty : _connected;
  bool get isReady =>
      _managesProfiles ? readySocketPaths.isNotEmpty : _connected && _ready;
  bool get isActive => _enabled;
  bool get outputEnabled => _outputEnabled;
  RelapseOutputState get outputState => _managesProfiles
      ? _profileServices[socketPath]?.outputState ?? RelapseOutputState.waiting
      : _outputState;
  String? get outputDetail => _managesProfiles
      ? _profileServices[socketPath]?.outputDetail
      : _outputDetail;

  /// RelapseGtk's `ui_bridge_is_ready`: the socket is ready, the UI channel is
  /// open and it acknowledged our configuration.
  bool get canExecute =>
      _managesProfiles
      ? executableSocketPaths.isNotEmpty
      : _enabled && _connected && _ready && _bridgeConfigured && (_bridgeChannel?.isOpen ?? false);

  bool get outputCaptureActive =>
      _managesProfiles
      ? _profileServices.values.any((service) => service.outputCaptureActive)
      : _bridgeConfigured && _outputEnabled;
  int? get session =>
      _managesProfiles ? _profileServices[socketPath]?.session : _session;
  int? sessionForSocketPath(String path) => _managesProfiles
      ? _profileServices[path]?.session
      : (path == socketPath ? _session : null);

  /// True once Relapse accepted the session-v2 UI channel, which wraps
  /// execution so scripts run inside the live game session.
  bool get sessionBridgeConfigured => _managesProfiles
      ? _profileServices.values.any((service) => service.sessionBridgeConfigured)
      : _bridgeConfigured;
  String? get error =>
      _managesProfiles ? _profileServices[socketPath]?.error : _error;

  /// Relapse profiles are identified by their socket filename, so a profile
  /// keeps the same label whoever discovered it.
  static String clientIdentifierForSocket(String path) {
    final label = profileLabelForSocket(path);
    return label == 'Default instance' ? 'Relapse' : 'Relapse · $label';
  }

  static String profileLabelForSocket(String path) {    final name = File(path).uri.pathSegments.last;
    if (name == 'relapse.sock') return 'Default instance';
    if (!name.startsWith('relapse-') || !name.endsWith('.sock')) {
      return 'Default instance';
    }
    return name.substring(8, name.length - 5);
  }

  /// RelapseGtk validates a profile name with the same rules as its profile
  /// store: 1–64 letters, digits, dots, underscores or hyphens.
  static bool isValidProfileName(String name) =>
      name.isNotEmpty &&
      name.length <= maximumProfileNameLength &&
      name != '.' &&
      name != '..' &&
      RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name);

  static bool isSupportedSocketName(String name) {
    if (name == 'relapse.sock') return true;
    if (!name.startsWith('relapse-') || !name.endsWith('.sock')) return false;
    return isValidProfileName(name.substring(8, name.length - 5));
  }

  Future<void> selectSocketPath(String path) async {
    if (!_managesProfiles ||
        !_profileServices.containsKey(path) ||
        path == socketPath) {
      return;
    }
    socketPath = path;
    if (!_disposed) notifyListeners();
  }

  Future<void> discoverSocketPaths({String? directory}) async {
    if (!_managesProfiles || _discovering || _disposed) return;
    _discovering = true;
    try {
      final root = directory ?? profileDirectory;
      final candidates = <String>[];
      await for (final entity in Directory(
        root,
      ).list(followLinks: false).take(4096)) {
        final path = entity.path;
        final name = File(path).uri.pathSegments.last;
        if (!isSupportedSocketName(name)) continue;
        if (path.length > maximumSocketPathBytes) continue;
        if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.unixDomainSock) {
          continue;
        }
        candidates.add(path);
        if (candidates.length == maximumSocketPaths) break;
      }
      final owned = await _ownedPaths(candidates);
      final paths = <String>[];
      for (final path in candidates) {
        if (!owned.contains(path)) continue;
        if (!await isListening(path)) continue;
        paths.add(path);
      }
      paths.sort();
      await _syncProfileServices(paths);
      if (!_profileServices.containsKey(socketPath)) {
        socketPath = paths.contains('$root/relapse.sock')
            ? '$root/relapse.sock'
            : (paths.isEmpty ? defaultSocketPath : paths.first);
      }
      final visiblePaths = [...paths];
      if (visiblePaths.isEmpty && socketPath == defaultSocketPath) {
        visiblePaths.add(defaultSocketPath);
      }
      if (!_samePaths(visiblePaths, _socketPaths)) {
        _socketPaths
          ..clear()
          ..addAll(visiblePaths);
        if (!_disposed) notifyListeners();
      }
    } on Object catch (error) {
      if (_enabled) _error = _safeDetail(error.toString());
    } finally {
      _discovering = false;
    }
  }

  static bool _samePaths(List<String> a, List<String> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((same) => same);

  /// RelapseGtk only trusts sockets owned by the current user. `stat` answers
  /// for every candidate in one call, where a probe per socket would spawn a
  /// process for each one on every discovery pass.
  static Future<Set<String>> _ownedPaths(List<String> candidates) async {
    if (candidates.isEmpty) return const {};
    try {
      final uid = await (_uidFuture ??= _readUid());
      final result = await Process.run('stat', [
        '-c',
        '%u\t%n',
        '--',
        ...candidates,
      ]);
      final owned = <String>{};
      for (final line in const LineSplitter().convert('${result.stdout}')) {
        final separator = line.indexOf('\t');
        if (separator <= 0) continue;
        if (int.tryParse(line.substring(0, separator)) != uid) continue;
        owned.add(line.substring(separator + 1));
      }
      return owned;
    } on Object {
      return const {};
    }
  }

  static Future<int> _readUid() async {
    final result = await Process.run('id', ['-u']);
    if (result.exitCode != 0) throw const ProcessException('id', ['-u']);
    return int.parse(result.stdout.toString().trim());
  }

  /// A full Unix accept queue still counts as a live listener in RelapseGtk
  /// (`EAGAIN`/`EINPROGRESS`), so discovery never stalls on one profile.
  static Future<bool> isListening(String path) async {
    try {
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 150),
      );
      socket.destroy();
      return true;
    } on SocketException catch (error) {
      final code = error.osError?.errorCode;
      return code == 11 || code == 115;
    } on Object {
      return false;
    }
  }

  Future<void> _syncProfileServices(List<String> paths) async {
    for (final path in paths) {
      if (_profileServices.containsKey(path)) continue;
      final service = RelapseGtkService(
        socketPath: path,
        reconnectInterval: reconnectInterval,
        handshakeTimeout: handshakeTimeout,
        handshakeRetry: handshakeRetry,
        maximumScriptBytes: maximumScriptBytes,
        manageProfiles: false,
        profileDirectory: profileDirectory,
        profileIdentifier: clientIdentifierForSocket(path),
        sessionScriptLoader: _sessionScriptLoader,
        outputEnabled: _outputEnabled,
      );
      _profileServices[path] = service;
      _profileLogs[path] = service.logReceived.listen((entry) {
        if (!_logs.isClosed) _logs.add(entry);
      });
      service.addListener(_profileChanged);
      if (_enabled) await service.start();
    }
    for (final path in _profileServices.keys
        .where((path) => !paths.contains(path))
        .toList()) {
      final service = _profileServices.remove(path)!;
      await _profileLogs.remove(path)?.cancel();
      service.removeListener(_profileChanged);
      await service.disposeAsync();
    }
  }

  void _profileChanged() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (_disposed || _enabled) return;
    _enabled = true;
    _error = null;
    if (_managesProfiles) {
      await discoverSocketPaths();
      _discoveryTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(discoverSocketPaths()),
      );
      notifyListeners();
      return;
    }
    _reconnectTimer = Timer.periodic(
      reconnectInterval,
      (_) => unawaited(_connectMain()),
    );
    notifyListeners();
    await _connectMain();
  }

  Future<void> stop() async {
    if (!_enabled &&
        _main == null &&
        _bridgeChannel == null &&
        _profileServices.isEmpty) {
      return;
    }
    _enabled = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    _bridgeTimer?.cancel();
    _bridgeTimer = null;
    _bridgeDeadline = null;
    final bridgeChannel = _bridgeChannel;
    final main = _main;
    _bridgeChannel = null;
    _main = null;
    _bridgeConfigured = false;
    await bridgeChannel?.close();
    await main?.close();
    for (final subscription in _profileLogs.values) {
      await subscription.cancel();
    }
    _profileLogs.clear();
    for (final service in _profileServices.values) {
      service.removeListener(_profileChanged);
      await service.disposeAsync();
    }
    _profileServices.clear();
    _connected = false;
    _ready = false;
    _session = null;
    _helloReceived = false;
    _bridgeSession = 0;
    _bridgeScriptIds.clear();
    _error = null;
    _outputState = RelapseOutputState.off;
    _outputDetail = null;
    _scriptNames.clear();
    if (!_disposed) notifyListeners();
  }

  /// RelapseGtk's "Redirect script output" switch: `ui_bridge_set_output_enabled`.
  /// It reconfigures an open UI channel and restarts a stopped bridge; the run
  /// wrapper itself stays available either way.
  void setOutputEnabled(bool value) {
    if (_outputEnabled == value) return;
    _outputEnabled = value;
    if (_managesProfiles) {
      for (final service in _profileServices.values) {
        service.setOutputEnabled(value);
      }
      if (!_disposed) notifyListeners();
      return;
    }
    final channel = _bridgeChannel;
    if (channel != null && channel.isOpen) {
      _configureBridge(channel);
    } else if (_outputState != RelapseOutputState.connecting) {
      _bridgeSession = _ready ? (_session ?? 0) : 0;
      _startBridge();
    }
    if (!_disposed) notifyListeners();
  }

  Future<int> execute(
    String source, {
    required String name,
    String? targetSocketPath,
  }) async {
    if (_managesProfiles) {
      final service = _profileServices[targetSocketPath ?? socketPath];
      if (service == null) {
        throw StateError('Relapse instance is no longer available.');
      }
      return service.execute(source, name: name);
    }
    if (!canExecute || _main == null) {
      throw StateError(
        'Relapse is still preparing the UI channel for this game session.',
      );
    }
    if (utf8.encode(source).length > maximumScriptBytes) {
      throw ArgumentError('Script exceeds the $maximumScriptBytes byte limit.');
    }
    final cleanName = name.trim();
    final scriptName = cleanName.isNotEmpty && cleanName.length <= 255
        ? cleanName
        : 'editor.luau';
    final wrappedSource =
        'getgenv().__relapsegtk_session_v2.execute('
        '${_luaString(source)},${_luaString(scriptName)})';
    if (utf8.encode(wrappedSource).length > maximumScriptBytes) {
      throw ArgumentError(
        'Wrapped script exceeds the $maximumScriptBytes byte limit.',
      );
    }
    final id = _nextScriptId++;
    _scriptNames[id] = scriptName;
    try {
      _main!.send({
        'op': 'execute',
        'script_id': id,
        'session': _session,
        'name': executeScriptName,
        'source': wrappedSource,
      });
    } on Object {
      _scriptNames.remove(id);
      rethrow;
    }
    return id;
  }

  Future<void> _connectMain() async {
    if (_managesProfiles || !_enabled || _disposed || _connecting || _main != null) {
      return;
    }
    _connecting = true;
    _helloReceived = false;
    final selectedPath = socketPath;
    try {
      final channel = await _RelapseChannel.connect(
        socketPath: selectedPath,
        channelName: mainChannel,
        onMessage: _onMainMessage,
        onClosed: _onMainClosed,
      );
      if (!_enabled || _disposed || socketPath != selectedPath) {
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
    _helloReceived = false;
    _syncBridge();
    if (error != null) _error = _safeDetail(error.toString());
    if (_enabled && !_disposed) notifyListeners();
  }

  void _onMainMessage(_RelapseChannel channel, Map<String, dynamic> message) {
    if (_main != null && !identical(_main, channel)) return;
    final type = message['type'];
    if (!_helloReceived && type != 'hello') {
      _protocolError('Relapse did not begin with a hello message.');
      return;
    }
    if (_helloReceived && type == 'hello') {
      _protocolError('Relapse sent more than one hello message.');
      return;
    }
    if (type == 'hello' || type == 'status') {
      final ready = message['ready'];
      final session = _integer(message['session']);
      if (ready is! bool || session == null || (ready && session == 0)) {
        _protocolError('Relapse sent an invalid session status.');
        return;
      }
      _helloReceived = true;
      _connected = true;
      _ready = ready;
      _session = session;
      _error = null;
      _syncBridge();
      notifyListeners();
      return;
    }
    if (type == 'exec_result') {
      final id = _integer(message['script_id'], maximum: 1 << 53);
      final phase = message['phase'];
      if (id == null || (phase != 'submitted' && phase != 'error')) {
        _protocolError('Relapse sent an invalid script result.');
        return;
      }
      final detail = _safeDetail(
        message['detail']?.toString() ?? 'request failed',
      );
      if (_bridgeScriptIds.remove(id)) {
        if (phase == 'error') {
          _failBridge(
            _safeDetail(
              message['detail']?.toString() ?? 'UI channel setup failed.',
            ),
          );
        }
        return;
      }
      // RelapseGtk only reports ids it is still waiting for. A result that
      // arrives after a session change belongs to a discarded bridge request.
      final name = _scriptNames.remove(id);
      if (name == null) return;
      _emitLog(
        phase == 'submitted' ? 'success' : 'error',
        phase == 'submitted'
            ? '$name submitted to Relapse.'
            : '$name failed: $detail',
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

  /// Runs the UI-channel script for a new game session and arms the retry that
  /// waits for Relapse to publish the channel. This is `ui_bridge_sync` +
  /// `start` in RelapseGtk's bridge.c.
  void _syncBridge() {
    final session = _ready ? (_session ?? 0) : 0;
    if (session == _bridgeSession) return;
    _bridgeSession = session;
    _startBridge();
  }

  void _startBridge() {
    _stopBridge();
    if (_bridgeSession <= 0) {
      _outputState = RelapseOutputState.waiting;
      _outputDetail = 'Waiting for a game';
      if (!_disposed) notifyListeners();
      return;
    }
    final id = _nextScriptId++;
    _bridgeScriptIds.add(id);
    _outputState = RelapseOutputState.connecting;
    _outputDetail = 'Starting UI channel…';
    _bridgeDeadline = DateTime.now().add(handshakeTimeout);
    _startBridgeTimer();
    if (!_disposed) notifyListeners();
    unawaited(_runBridgeScript(id));
  }

  Future<void> _runBridgeScript(int id) async {
    try {
      final source = await _sessionScriptLoader();
      if (!_enabled ||
          _disposed ||
          !_bridgeScriptIds.contains(id) ||
          _bridgeSession <= 0 ||
          _main == null) {
        return;
      }
      _main!.send({
        'op': 'execute',
        'script_id': id,
        'session': _session,
        'name': sessionScriptName,
        'source': source,
      });
    } on Object catch (error) {
      _bridgeScriptIds.remove(id);
      _failBridge(
        'Could not start the UI channel: ${_safeDetail(error.toString())}',
      );
      return;
    }
    _tickBridge();
  }

  void _startBridgeTimer() {
    _bridgeTimer?.cancel();
    _bridgeTimer = Timer.periodic(handshakeRetry, (_) => _tickBridge());
  }

  void _tickBridge() {
    if (!_enabled || _disposed) return;
    if (_bridgeConfigured) return;
    final deadline = _bridgeDeadline;
    if (deadline == null) return;
    if (DateTime.now().isAfter(deadline)) {
      _failBridge(
        'UI channel setup timed out. Toggle output redirection to retry.',
      );
      return;
    }
    if (_bridgeChannel == null && !_bridgeConnecting && _ready) {
      unawaited(_connectBridge());
    }
  }

  Future<void> _connectBridge() async {
    if (!_enabled ||
        _disposed ||
        !_ready ||
        _bridgeChannel != null ||
        _bridgeConnecting) {
      return;
    }
    _bridgeConnecting = true;
    final selectedPath = socketPath;
    try {
      final channel = await _RelapseChannel.connect(
        socketPath: selectedPath,
        channelName: sessionChannel,
        onMessage: _onBridgeMessage,
        onClosed: _onBridgeClosed,
        timeout: const Duration(milliseconds: 250),
      );
      if (!_enabled ||
          _disposed ||
          !_ready ||
          socketPath != selectedPath ||
          _bridgeSession <= 0) {
        await channel.close();
        return;
      }
      if (!channel.isOpen) {
        throw const SocketException('Relapse UI channel closed during setup.');
      }
      _bridgeChannel = channel;
      _configureBridge(channel);
    } on Object {
      // Relapse publishes this channel only after session.luau has run, and it
      // answers `unknown_channel` until then. The retry timer owns the wait, as
      // in RelapseGtk; the deadline above decides when it is hopeless.
    } finally {
      _bridgeConnecting = false;
    }
  }

  void _configureBridge(_RelapseChannel channel) {
    try {
      channel.send({
        'op': 'configure',
        'version': sessionVersion,
        'redirect': _outputEnabled,
      });
    } on Object catch (error) {
      _failBridge(
        'Could not configure the UI channel: ${_safeDetail(error.toString())}',
      );
      return;
    }
    _bridgeConfigured = false;
    _bridgeDeadline = DateTime.now().add(handshakeTimeout);
    _outputState = RelapseOutputState.connecting;
    _outputDetail = 'Connecting…';
    _startBridgeTimer();
    if (!_disposed) notifyListeners();
  }

  void _onBridgeClosed(_RelapseChannel channel, [Object? error]) {
    if (!identical(_bridgeChannel, channel)) return;
    _bridgeChannel = null;
    _bridgeConfigured = false;
    if (_enabled && _ready && !_disposed) {
      _outputState = RelapseOutputState.connecting;
      _outputDetail = 'Reconnecting…';
      _bridgeDeadline = DateTime.now().add(handshakeTimeout);
      _startBridgeTimer();
      _tickBridge();
    }
    if (!_disposed) notifyListeners();
  }

  void _onBridgeMessage(_RelapseChannel channel, Map<String, dynamic> message) {
    if (!identical(_bridgeChannel, channel)) return;
    final type = message['type'];
    if (type == 'configured') {
      final version = _integer(message['version'], maximum: 1 << 31);
      final redirect = message['redirect'];
      if (version != sessionVersion || redirect is! bool) {
        _failBridge('Invalid UI channel message. Toggle output redirection to retry.');
        return;
      }
      // A toggle racing the ack produces a stale answer; the fresh configure is
      // already on the wire, so RelapseGtk ignores it rather than failing.
      if (redirect != _outputEnabled) return;
      _bridgeConfigured = true;
      _bridgeTimer?.cancel();
      _bridgeTimer = null;
      _bridgeDeadline = null;
      _outputState = _outputEnabled
          ? RelapseOutputState.active
          : RelapseOutputState.off;
      _outputDetail = _outputEnabled ? 'Capturing' : 'Output off';
      notifyListeners();
      return;
    }
    if (!_bridgeConfigured) {
      // Output can race the configuration ack; RelapseGtk drops it as well.
      if (type == 'output' || type == 'dropped') return;
      _failBridge('Invalid UI channel message. Toggle output redirection to retry.');
      return;
    }
    if (type == 'failed') {
      final detail = message['detail'];
      if (detail is! String || utf8.encode(detail).length > 4096) {
        _failBridge('Invalid UI channel message. Toggle output redirection to retry.');
        return;
      }
      _failBridge(_safeDetail(detail));
      return;
    }
    if (type == 'output') {
      final entries = message['entries'];
      final dropped = _integer(message['dropped']);
      if (entries is! List ||
          entries.isEmpty ||
          entries.length > maximumOutputEntries ||
          dropped == null) {
        _failBridge('Invalid UI channel message. Toggle output redirection to retry.');
        return;
      }
      final validated = _validatedOutputEntries(entries);
      if (validated == null) {
        _failBridge('Invalid UI channel message. Toggle output redirection to retry.');
        return;
      }
      if (!_outputEnabled) return;
      for (final entry in validated) {
        _emitLog(entry.key, entry.value);
      }
      if (dropped > 0) _emitDropped(dropped);
      return;
    }
    if (type == 'dropped') {
      final count = _integer(message['count'], minimum: 1);
      if (count == null) {
        _failBridge('Invalid UI channel message. Toggle output redirection to retry.');
        return;
      }
      if (_outputEnabled) _emitDropped(count);
      return;
    }
    _failBridge('Invalid UI channel message. Toggle output redirection to retry.');
  }

  List<MapEntry<String, String>>? _validatedOutputEntries(List entries) {
    final validated = <MapEntry<String, String>>[];
    for (final entry in entries) {
      if (entry is! Map || entry['level'] is! String || entry['text'] is! String) {
        return null;
      }
      final level = entry['level'] as String;
      final text = entry['text'] as String;
      if (!const {'print', 'warn', 'error', 'info'}.contains(level) ||
          utf8.encode(text).length > maximumOutputTextBytes) {
        return null;
      }
      validated.add(MapEntry(level, text));
    }
    return validated;
  }

  void _emitDropped(int count) => _emitLog(
    'warn',
    '$count messages dropped: output arrived too quickly.',
  );

  void _stopBridge() {
    _bridgeTimer?.cancel();
    _bridgeTimer = null;
    _bridgeDeadline = null;
    _bridgeConfigured = false;
    _bridgeScriptIds.clear();
    final channel = _bridgeChannel;
    _bridgeChannel = null;
    if (channel != null) unawaited(channel.close());
  }

  void _failBridge(String detail) {
    _stopBridge();
    _bridgeDeadline = null;
    _outputState = RelapseOutputState.failed;
    _outputDetail = detail;
    _emitLog('error', detail);
    if (!_disposed) notifyListeners();
  }

  void _protocolError(String detail) {
    _error = detail;
    _emitLog('error', detail);
    final main = _main;
    if (main != null) unawaited(main.close());
  }

  /// RelapseGtk treats every numeric field as an integer that may arrive as an
  /// integral double, because Lua serialises its numbers that way.
  static int? _integer(
    Object? value, {
    int minimum = 0,
    int maximum = 0x7fffffff,
  }) {
    final int number;
    if (value is int) {
      number = value;
    } else if (value is double) {
      if (!value.isFinite || value < minimum || value > maximum) return null;
      number = value.toInt();
      if (number != value) return null;
    } else {
      return null;
    }
    return number < minimum || number > maximum ? null : number;
  }

  static String _luaString(String value) {
    final escaped = StringBuffer('"');
    for (final unit in utf8.encode(value)) {
      if (unit == 34 || unit == 92) {
        escaped.write('\\${String.fromCharCode(unit)}');
      } else if (unit < 32 || unit == 127) {
        escaped.write('\\${unit.toString().padLeft(3, '0')}');
      } else {
        escaped.writeCharCode(unit);
      }
    }
    return '${escaped.toString()}"';
  }

  Future<void> disposeAsync() async {
    await stop();
    if (!_logs.isClosed) await _logs.close();
  }

  void _emitLog(String level, String message, {String? executionId}) {
    final clean = _safeDetail(message);
    if (_logs.isClosed) return;
    _logs.add(
      BridgeLogEntry(
        timestampUtc: DateTime.now().toUtc(),
        level: level,
        message: clean,
        identifier: _profileIdentifier,
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
    unawaited(disposeAsync());
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
          final limit = message['max_message_bytes'];
          if (message['ok'] != true ||
              message['version'] != RelapseGtkService.protocolVersion ||
              limit is! int ||
              limit < 1) {
            throw FormatException(
              message['error'] is String
                  ? message['error'] as String
                  : 'Invalid Relapse channel handshake.',
            );
          }
          _maximumMessageBytes = limit.clamp(1, 8 * 1024 * 1024);
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
