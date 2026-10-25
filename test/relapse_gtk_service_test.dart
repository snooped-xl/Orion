import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/bridge_models.dart';
import 'package:orion/services/relapse_gtk_service.dart';

void main() {
  test('executes in a ready session and forwards Relapse output', () async {
    final server = await _FakeRelapseServer.start();
    final service = RelapseGtkService(
      socketPath: server.path,
      reconnectInterval: const Duration(milliseconds: 50),
      outputScriptLoader: () async => '-- output capture fixture',
    );
    final output = service.logReceived.firstWhere(
      (entry) => entry.message == 'hello from Relapse',
    );
    addTearDown(service.dispose);
    addTearDown(server.close);

    await service.start();
    await server.mainReady.future.timeout(const Duration(seconds: 2));
    await _waitFor(() => service.isReady);
    await server.outputSubscribed.future.timeout(const Duration(seconds: 2));
    await _waitFor(() => service.outputCaptureActive);
    expect(service.outputCaptureActive, isTrue);

    final id = await service.execute('print("hello")', name: 'hello.lua');
    final request = await server.userScript.future.timeout(
      const Duration(seconds: 2),
    );
    expect(request['script_id'], id);
    expect(request['session'], 42);
    expect(request['name'], 'hello.lua');
    expect(request['source'], 'print("hello")');

    server.sendOutput('hello from Relapse');
    expect((await output.timeout(const Duration(seconds: 2))).level, 'print');
  });

  test(
    'output before the subscription acknowledgement keeps the session up',
    () async {
      final server = await _FakeRelapseServer.start(
        outputBeforeSubscribed: true,
      );
      final service = RelapseGtkService(
        socketPath: server.path,
        reconnectInterval: const Duration(milliseconds: 50),
        outputScriptLoader: () async => '-- output capture fixture',
      );
      final output = service.logReceived.firstWhere(
        (entry) => entry.message == 'early Relapse output',
      );
      addTearDown(service.dispose);
      addTearDown(server.close);

      await service.start();
      await server.mainReady.future.timeout(const Duration(seconds: 2));
      await server.outputSubscribed.future.timeout(const Duration(seconds: 2));
      expect((await output.timeout(const Duration(seconds: 2))).level, 'print');
      expect(service.outputCaptureActive, isTrue);
      expect(service.isReady, isTrue);

      final captureError = service.logReceived.firstWhere(
        (entry) => entry.message == 'Relapse sent an invalid output batch.',
      );
      server.sendInvalidOutput();
      await captureError.timeout(const Duration(seconds: 2));
      expect(service.outputCaptureActive, isFalse);
      expect(service.isReady, isTrue);

      final id = await service.execute(
        'print("still connected")',
        name: 'test.lua',
      );
      final request = await server.userScript.future.timeout(
        const Duration(seconds: 2),
      );
      expect(request['script_id'], id);
      expect(service.isReady, isTrue);
    },
  );

  test(
    'session.v2 channel configures execution wrapper and deduplicates output',
    () async {
      final server = await _FakeRelapseServer.start(enableSessionChannel: true);
      final service = RelapseGtkService(
        socketPath: server.path,
        reconnectInterval: const Duration(milliseconds: 50),
        outputScriptLoader: () async => '-- output capture fixture',
        sessionScriptLoader: () async => '-- session bridge fixture',
      );
      final logs = <String>[];
      final sub = service.logReceived.listen((entry) => logs.add(entry.message));
      addTearDown(sub.cancel);
      addTearDown(service.dispose);
      addTearDown(server.close);

      await service.start();
      await server.mainReady.future.timeout(const Duration(seconds: 2));
      await server.sessionConfigured.future.timeout(const Duration(seconds: 2));
      await _waitFor(() => service.sessionBridgeConfigured);
      expect(service.outputCaptureActive, isTrue);

      final id = await service.execute('print("v2")', name: 'my script.lua');
      final request = await server.userScript.future.timeout(
        const Duration(seconds: 2),
      );
      expect(request['script_id'], id);
      expect(request['name'], 'relapsegtk-execute.luau');
      expect(
        request['source'],
        'getgenv().__relapsegtk_session_v2.execute("print(\\"v2\\")","my script.lua")',
      );

      // The negotiated session channel replaces the legacy output capture, so
      // Orion must not open the v1 channel or publish its entries twice.
      server.sendSessionOutput('from session v2');
      server.sendOutput('duplicate from output v1');
      await _waitFor(() => logs.contains('from session v2'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(logs.where((message) => message == 'from session v2'), hasLength(1));
      expect(server.outputSubscribed.isCompleted, isFalse);
      expect(logs, isNot(contains('duplicate from output v1')));
    },
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
        enableSessionChannel: true,
      );
      final altServer = await _FakeRelapseServer.startInDirectory(
        directory,
        socketName: 'relapse-alt-1.sock',
        session: 202,
        enableSessionChannel: true,
      );
      final service = RelapseGtkService(
        socketPath: defaultServer.path,
        reconnectInterval: const Duration(milliseconds: 50),
        manageProfiles: true,
        profileDirectory: directory.path,
        outputScriptLoader: () async => '-- output capture fixture',
        sessionScriptLoader: () async => '-- session bridge fixture',
      );
      final logs = <BridgeLogEntry>[];
      final sub = service.logReceived.listen(logs.add);
      addTearDown(sub.cancel);
      addTearDown(service.dispose);
      addTearDown(defaultServer.close);
      addTearDown(altServer.close);

      await service.start();
      await defaultServer.mainReady.future.timeout(const Duration(seconds: 2));
      await altServer.mainReady.future.timeout(const Duration(seconds: 2));
      await _waitFor(() => service.readySocketPaths.length == 2);

      expect(
        service.socketPaths,
        containsAll([defaultServer.path, altServer.path]),
      );
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

      await _waitFor(() => service.sessionBridgeConfigured);

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
      final altLog = logs.firstWhere(
        (entry) => entry.message == 'hello from alt',
      );
      expect(altLog.identifier, 'Relapse · alt-1');
    },
  );
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
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
    required this.outputBeforeSubscribed,
    required this.enableSessionChannel,
  }) {
    server.listen(_accept);
  }

  final Directory directory;
  final ServerSocket server;
  final String socketName;
  final int session;
  final bool outputBeforeSubscribed;
  final bool enableSessionChannel;
  final Completer<void> mainReady = Completer<void>();
  final Completer<void> outputSubscribed = Completer<void>();
  final Completer<void> sessionConfigured = Completer<void>();
  final Completer<Map<String, dynamic>> userScript =
      Completer<Map<String, dynamic>>();
  final Set<_Peer> _peers = {};
  _Peer? _outputPeer;
  _Peer? _sessionPeer;

  String get path => '${directory.path}/$socketName';

  static Future<_FakeRelapseServer> start({
    bool outputBeforeSubscribed = false,
    bool enableSessionChannel = false,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'orion-relapse-test-',
    );
    return startInDirectory(
      directory,
      outputBeforeSubscribed: outputBeforeSubscribed,
      enableSessionChannel: enableSessionChannel,
    );
  }

  static Future<_FakeRelapseServer> startInDirectory(
    Directory directory, {
    String socketName = 'relapse.sock',
    int session = 42,
    bool outputBeforeSubscribed = false,
    bool enableSessionChannel = false,
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
      outputBeforeSubscribed: outputBeforeSubscribed,
      enableSessionChannel: enableSessionChannel,
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
      if (peer.channel == 'relapsegtk.session.v2' && !enableSessionChannel) {
        peer.close();
        return;
      }
      peer.send({
        'ok': true,
        'version': 1,
        'max_message_bytes': 8 * 1024 * 1024,
      });
      if (peer.channel == '@main') {
        peer.send({'type': 'hello', 'ready': true, 'session': session});
        if (!mainReady.isCompleted) mainReady.complete();
      } else if (peer.channel == 'relapsegtk.output.v1') {
        _outputPeer = peer;
      } else if (peer.channel == 'relapsegtk.session.v2') {
        _sessionPeer = peer;
      }
      return;
    }
    if (peer.channel == '@main' && message['op'] == 'execute') {
      final source = message['source'];
      if (source == '-- output capture fixture' ||
          source == '-- session bridge fixture') {
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
    if (peer.channel == 'relapsegtk.output.v1' &&
        message['op'] == 'subscribe') {
      if (outputBeforeSubscribed) peer.sendOutput('early Relapse output');
      peer.send({'type': 'subscribed', 'version': 1});
      if (!outputSubscribed.isCompleted) outputSubscribed.complete();
      return;
    }
    if (peer.channel == 'relapsegtk.session.v2' &&
        message['op'] == 'configure') {
      peer.send({'type': 'configured', 'version': 2, 'redirect': true});
      if (!sessionConfigured.isCompleted) sessionConfigured.complete();
    }
  }

  void sendOutput(String text) {
    _outputPeer?.sendOutput(text);
  }

  void sendSessionOutput(String text) {
    _sessionPeer?.sendOutput(text);
  }

  void sendInvalidOutput() {
    _outputPeer?.send({'type': 'output', 'entries': <Object?>[], 'dropped': 0});
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

  void sendOutput(String text) {
    send({
      'type': 'output',
      'entries': [
        {'level': 'print', 'text': text},
      ],
      'dropped': 0,
    });
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
