import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/bridge_models.dart';
import 'package:orion/services/relapse_gtk_service.dart';

/// Relapse support is Linux-only: it speaks over Unix sockets in `/tmp` and
/// checks socket ownership the way RelapseGtk does.
final _linuxOnly = Platform.isLinux ? null : 'Relapse support is Linux-only.';

/// A stand-in for Relapse itself, reproducing what the real executor does:
///
///  * `@main` answers `hello` with a ready session and accepts scripts;
///  * `relapsegtk.session.v2` stays unknown until `session.luau` has run, so
///    early connection attempts are rejected exactly like the real server;
///  * Lua numbers arrive as JSON doubles (`{"version": 2.0, "dropped": 0.0}`).
void main() {
  test(
    'waits for the UI channel, then executes through the session wrapper',
    () async {
      final server = await _FakeRelapseServer.start(
        publishOnSessionScript: false,
      );
      final service = RelapseGtkService(
        socketPath: server.path,
        reconnectInterval: const Duration(milliseconds: 50),
        handshakeRetry: const Duration(milliseconds: 20),
        sessionScriptLoader: () async => '-- session bridge fixture',
      );
      final logs = <String>[];
      final subscription = service.logReceived.listen(
        (entry) => logs.add(entry.message),
      );
      addTearDown(subscription.cancel);
      addTearDown(service.dispose);
      addTearDown(server.close);

      await service.start();
      await _waitFor(() => service.isReady);
      await _waitFor(() => server.sessionReady);

      // RelapseGtk refuses to submit before the wrapper exists; so does Orion,
      // because unwrapped code would skip the live game session entirely.
      expect(service.canExecute, isFalse);
      expect(service.outputState, RelapseOutputState.connecting);
      await expectLater(
        service.execute('print("too early")', name: 'early.lua'),
        throwsStateError,
      );
      expect(server.userScript.isCompleted, isFalse);

      server.channelPublished = true;
      await _waitFor(() => service.canExecute);
      expect(service.outputCaptureActive, isTrue);

      final id = await service.execute('print("v2")', name: 'my script.lua');
      final request = await server.userScript.future.timeout(
        const Duration(seconds: 2),
      );
      expect(request['script_id'], id);
      expect(request['session'], 42);
      expect(request['name'], 'relapsegtk-execute.luau');
      expect(
        request['source'],
        'getgenv().__relapsegtk_session_v2.execute("print(\\"v2\\")","my script.lua")',
      );

      server.sendSessionOutput('from session v2');
      await _waitFor(() => logs.contains('from session v2'));
      expect(logs.where((message) => message == 'from session v2'), hasLength(1));
    },
    skip: _linuxOnly,
  );

  test(
    'retries a rejected UI channel until Relapse publishes it',
    () async {
      final server = await _FakeRelapseServer.start(channelRejections: 3);
      final service = RelapseGtkService(
        socketPath: server.path,
        reconnectInterval: const Duration(milliseconds: 50),
        handshakeRetry: const Duration(milliseconds: 20),
        sessionScriptLoader: () async => '-- session bridge fixture',
      );
      addTearDown(service.dispose);
      addTearDown(server.close);

      await service.start();
      await _waitFor(() => service.canExecute);
      expect(server.channelAttempts, greaterThan(3));
      expect(service.error, isNull);
    },
    skip: _linuxOnly,
  );

  test(
    'redirect toggle reconfigures the channel and hides output while off',
    () async {
      final server = await _FakeRelapseServer.start();
      final service = RelapseGtkService(
        socketPath: server.path,
        reconnectInterval: const Duration(milliseconds: 50),
        sessionScriptLoader: () async => '-- session bridge fixture',
      );
      final logs = <String>[];
      final subscription = service.logReceived.listen(
        (entry) => logs.add(entry.message),
      );
      addTearDown(subscription.cancel);
      addTearDown(service.dispose);
      addTearDown(server.close);

      await service.start();
      await _waitFor(() => service.canExecute);
      expect(server.configures.single['redirect'], true);

      service.setOutputEnabled(false);
      await _waitFor(() => server.configures.length == 2);
      expect(server.configures.last['redirect'], false);
      await _waitFor(() => service.outputState == RelapseOutputState.off);
      expect(service.canExecute, isTrue);
      expect(service.outputCaptureActive, isFalse);

      server.sendSessionOutput('while redirection is off');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(logs, isNot(contains('while redirection is off')));

      service.setOutputEnabled(true);
      await _waitFor(() => server.configures.length == 3);
      await _waitFor(() => service.outputCaptureActive);
      server.sendSessionOutput('back on');
      await _waitFor(() => logs.contains('back on'));
    },
    skip: _linuxOnly,
  );

  test(
    'a stale configuration ack keeps the bridge waiting instead of failing',
    () async {
      final server = await _FakeRelapseServer.start(deferAcks: true);
      final service = RelapseGtkService(
        socketPath: server.path,
        reconnectInterval: const Duration(milliseconds: 50),
        handshakeRetry: const Duration(milliseconds: 20),
        sessionScriptLoader: () async => '-- session bridge fixture',
      );
      addTearDown(service.dispose);
      addTearDown(server.close);

      await service.start();
      await _waitFor(() => server.configures.isNotEmpty);
      expect(service.canExecute, isFalse);

      // The ack echoes the opposite redirect, so it belongs to an earlier
      // toggle. RelapseGtk ignores it; failing here would break the session.
      server.sendConfigured(stale: true);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(service.canExecute, isFalse);
      expect(service.outputState, RelapseOutputState.connecting);

      server.sendConfigured();
      await _waitFor(() => service.canExecute);
      expect(service.outputState, RelapseOutputState.active);
    },
    skip: _linuxOnly,
  );

  test(
    'rejects an invalid output batch and stops offering execution',
    () async {
      final server = await _FakeRelapseServer.start();
      final service = RelapseGtkService(
        socketPath: server.path,
        reconnectInterval: const Duration(milliseconds: 50),
        sessionScriptLoader: () async => '-- session bridge fixture',
      );
      final errors = <String>[];
      final subscription = service.logReceived.listen(
        (entry) => errors.add(entry.message),
      );
      addTearDown(subscription.cancel);
      addTearDown(service.dispose);
      addTearDown(server.close);

      await service.start();
      await _waitFor(() => service.canExecute);

      server.sendRawSession({
        'type': 'output',
        'entries': [
          {'level': 'print', 'text': 'fine'},
        ],
        'dropped': -1,
      });
      await _waitFor(() => !service.canExecute);
      expect(service.outputState, RelapseOutputState.failed);
      expect(
        errors.last,
        'Invalid UI channel message. Toggle output redirection to retry.',
      );
      await expectLater(
        service.execute('print("blocked")', name: 'blocked.lua'),
        throwsStateError,
      );
    },
    skip: _linuxOnly,
  );

  test(
    'reports a UI channel that never answers within the deadline',
    () async {
      final server = await _FakeRelapseServer.start(
        publishOnSessionScript: false,
      );
      final service = RelapseGtkService(
        socketPath: server.path,
        reconnectInterval: const Duration(milliseconds: 50),
        handshakeRetry: const Duration(milliseconds: 20),
        handshakeTimeout: const Duration(milliseconds: 250),
        sessionScriptLoader: () async => '-- session bridge fixture',
      );
      final errors = <String>[];
      final subscription = service.logReceived.listen(
        (entry) => errors.add(entry.message),
      );
      addTearDown(subscription.cancel);
      addTearDown(service.dispose);
      addTearDown(server.close);

      await service.start();
      await _waitFor(() => service.outputState == RelapseOutputState.failed);
      expect(
        errors,
        contains(
          'UI channel setup timed out. Toggle output redirection to retry.',
        ),
      );
      expect(service.canExecute, isFalse);
    },
    skip: _linuxOnly,
  );

  test(
    'reports dropped output in RelapseGtk order with its exact wording',
    () async {
      final server = await _FakeRelapseServer.start();
      final service = RelapseGtkService(
        socketPath: server.path,
        reconnectInterval: const Duration(milliseconds: 50),
        sessionScriptLoader: () async => '-- session bridge fixture',
      );
      final logs = <BridgeLogEntry>[];
      final subscription = service.logReceived.listen(logs.add);
      addTearDown(subscription.cancel);
      addTearDown(service.dispose);
      addTearDown(server.close);

      await service.start();
      await _waitFor(() => service.canExecute);

      server.sendSessionOutput('after a drop', dropped: 3.0);
      await _waitFor(() => logs.any((entry) => entry.level == 'warn'));
      expect(
        logs.map((entry) => entry.message),
        containsAllInOrder([
          'after a drop',
          '3 messages dropped: output arrived too quickly.',
        ]),
      );
    },
    skip: _linuxOnly,
  );

  test(
    'discovers multiple Relapse profile sockets and executes on selected profiles',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'orion-relapse-multi-',
      );
      final defaultServer = await _FakeRelapseServer.startInDirectory(
        directory,
        socketName: 'relapse.sock',
        session: 101,
      );
      final altServer = await _FakeRelapseServer.startInDirectory(
        directory,
        socketName: 'relapse-alt-1.sock',
        session: 202,
      );
      final ignored = await _FakeRelapseServer.startInDirectory(
        directory,
        socketName: 'relapse-bad name.sock',
        session: 303,
      );
      final service = RelapseGtkService(
        socketPath: defaultServer.path,
        reconnectInterval: const Duration(milliseconds: 50),
        manageProfiles: true,
        profileDirectory: directory.path,
        sessionScriptLoader: () async => '-- session bridge fixture',
      );
      final logs = <BridgeLogEntry>[];
      final subscription = service.logReceived.listen(logs.add);
      addTearDown(subscription.cancel);
      addTearDown(service.dispose);
      addTearDown(defaultServer.close);
      addTearDown(altServer.close);
      addTearDown(ignored.close);

      await service.start();
      await _waitFor(() => service.executableSocketPaths.length == 2);
      expect(
        service.socketPaths,
        containsAll([defaultServer.path, altServer.path]),
      );
      expect(service.socketPaths, isNot(contains(ignored.path)));
      expect(service.sessionForSocketPath(defaultServer.path), 101);
      expect(service.sessionForSocketPath(altServer.path), 202);
      expect(
        RelapseGtkService.clientIdentifierForSocket(defaultServer.path),
        'Relapse',
      );
      expect(
        RelapseGtkService.clientIdentifierForSocket(altServer.path),
        'Relapse · alt-1',
      );

      final altId = await service.execute(
        'print("alt target")',
        name: 'alt.lua',
        targetSocketPath: altServer.path,
      );
      final altRequest = await altServer.userScript.future.timeout(
        const Duration(seconds: 2),
      );
      expect(altRequest['script_id'], altId);
      expect(altRequest['name'], 'relapsegtk-execute.luau');
      expect(
        altRequest['source'],
        'getgenv().__relapsegtk_session_v2.execute("print(\\"alt target\\")","alt.lua")',
      );
      expect(defaultServer.userScript.isCompleted, isFalse);

      altServer.sendSessionOutput('hello from alt');
      await _waitFor(
        () => logs.any((entry) => entry.message == 'hello from alt'),
      );
      expect(
        logs
            .firstWhere((entry) => entry.message == 'hello from alt')
            .identifier,
        'Relapse · alt-1',
      );
    },
    skip: _linuxOnly,
  );
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'Condition did not become true in time.');
}

class _FakeRelapseServer {
  _FakeRelapseServer(
    this.directory,
    this.server, {
    required this.socketName,
    required this.session,
    required this.channelRejections,
    required this.publishOnSessionScript,
    required this.deferAcks,
    required this.channelPublished,
  }) {
    server.listen(_accept);
  }

  final Directory directory;
  final ServerSocket server;
  final String socketName;
  final int session;
  final int channelRejections;
  final bool publishOnSessionScript;
  final bool deferAcks;
  final Completer<void> mainReady = Completer<void>();
  final Completer<Map<String, dynamic>> userScript =
      Completer<Map<String, dynamic>>();
  final List<Map<String, dynamic>> configures = [];
  final Set<_Peer> _peers = {};
  _Peer? _sessionPeer;
  bool channelPublished;
  bool sessionReady = false;
  int channelAttempts = 0;

  String get path => '${directory.path}/$socketName';

  static Future<_FakeRelapseServer> start({
    int channelRejections = 0,
    bool publishOnSessionScript = true,
    bool deferAcks = false,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'orion-relapse-test-',
    );
    return startInDirectory(
      directory,
      channelRejections: channelRejections,
      publishOnSessionScript: publishOnSessionScript,
      deferAcks: deferAcks,
    );
  }

  static Future<_FakeRelapseServer> startInDirectory(
    Directory directory, {
    String socketName = 'relapse.sock',
    int session = 42,
    int channelRejections = 0,
    bool publishOnSessionScript = true,
    bool deferAcks = false,
  }) async {
    final path = '${directory.path}/$socketName';
    final socket = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    return _FakeRelapseServer(
      directory,
      socket,
      socketName: socketName,
      session: session,
      channelRejections: channelRejections,
      publishOnSessionScript: publishOnSessionScript,
      deferAcks: deferAcks,
      channelPublished: false,
    );
  }

  void _accept(Socket socket) {
    late final _Peer peer;
    peer = _Peer(socket, (message) => _receive(peer, message));
    _peers.add(peer);
  }

  void _receive(_Peer peer, Map<String, dynamic> message) {
    if (peer.channel == null) {
      peer.channel = message['channel'] as String?;
      if (peer.channel == RelapseGtkService.sessionChannel) {
        channelAttempts++;
        if (!channelPublished || channelAttempts <= channelRejections) {
          // The real server answers unknown_channel until session.luau has
          // published the channel.
          peer.send({'ok': false, 'error': 'unknown_channel'});
          unawaited(peer.close());
          return;
        }
        _sessionPeer = peer;
      }
      peer.send({
        'ok': true,
        'version': 1,
        'max_message_bytes': 8 * 1024 * 1024,
      });
      if (peer.channel == RelapseGtkService.mainChannel) {
        peer.send({
          'type': 'hello',
          'ready': true,
          'session': session,
          'profile': 'default',
          'pid': 11,
        });
        if (!mainReady.isCompleted) mainReady.complete();
      }
      return;
    }
    if (peer.channel == RelapseGtkService.mainChannel &&
        message['op'] == 'execute') {
      if (message['source'] == '-- session bridge fixture') {
        sessionReady = true;
        if (publishOnSessionScript) channelPublished = true;
        peer.send({
          'type': 'exec_result',
          'script_id': message['script_id'],
          'phase': 'submitted',
        });
      } else if (!userScript.isCompleted) {
        userScript.complete(message);
      }
      return;
    }
    if (peer.channel == RelapseGtkService.sessionChannel &&
        message['op'] == 'configure') {
      configures.add(message);
      if (!deferAcks) sendConfigured();
    }
  }

  /// Answers the most recent configure. `stale` echoes the opposite redirect,
  /// which is what a toggle that raced the ack produces.
  void sendConfigured({bool stale = false}) {
    final redirect = configures.isEmpty
        ? false
        : configures.last['redirect'] as bool;
    // Lua numbers travel as doubles; keep the fake server honest about it.
    _sessionPeer?.send({
      'type': 'configured',
      'version': 2.0,
      'redirect': stale ? !redirect : redirect,
    });
  }

  void sendSessionOutput(String text, {double dropped = 0.0}) {
    _sessionPeer?.send({
      'type': 'output',
      'entries': [
        {'level': 'print', 'text': text},
      ],
      'dropped': dropped,
    });
  }

  void sendRawSession(Map<String, Object?> message) {
    _sessionPeer?.send(message);
  }

  Future<void> close() async {
    for (final peer in _peers) {
      await peer.close();
    }
    await server.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _Peer {
  _Peer(this.socket, this.onMessage) {
    socket.listen(
      _receive,
      onDone: () => _closed = true,
      onError: (_) => _closed = true,
      cancelOnError: true,
    );
  }

  final Socket socket;
  final void Function(Map<String, dynamic>) onMessage;
  final List<int> _pending = [];
  String? channel;
  bool _closed = false;

  void _receive(Uint8List chunk) {
    _pending.addAll(chunk);
    while (_pending.length >= 4) {
      final length = ByteData.sublistView(
        Uint8List.fromList(_pending.sublist(0, 4)),
      ).getUint32(0, Endian.big);
      if (_pending.length < length + 4) return;
      final payload = Uint8List.fromList(_pending.sublist(4, length + 4));
      _pending.removeRange(0, length + 4);
      onMessage(
        Map<String, dynamic>.from(jsonDecode(utf8.decode(payload)) as Map),
      );
    }
  }

  void send(Map<String, Object?> message) {
    if (_closed) return;
    final payload = utf8.encode(jsonEncode(message));
    final frame = Uint8List(payload.length + 4);
    ByteData.sublistView(frame).setUint32(0, payload.length, Endian.big);
    frame.setRange(4, frame.length, payload);
    socket.add(frame);
  }

  Future<void> close() async {
    _closed = true;
    await socket.close();
  }
}
