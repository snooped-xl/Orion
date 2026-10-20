import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
    required this.outputBeforeSubscribed,
  }) {
    server.listen(_accept);
  }

  final Directory directory;
  final ServerSocket server;
  final bool outputBeforeSubscribed;
  final Completer<void> mainReady = Completer<void>();
  final Completer<void> outputSubscribed = Completer<void>();
  final Completer<Map<String, dynamic>> userScript =
      Completer<Map<String, dynamic>>();
  final Set<_Peer> _peers = {};
  _Peer? _outputPeer;

  String get path => '${directory.path}/relapse.sock';

  static Future<_FakeRelapseServer> start({
    bool outputBeforeSubscribed = false,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'orion-relapse-test-',
    );
    final path = '${directory.path}/relapse.sock';
    final socket = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    return _FakeRelapseServer(
      directory,
      socket,
      outputBeforeSubscribed: outputBeforeSubscribed,
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
      peer.send({
        'ok': true,
        'version': 1,
        'max_message_bytes': 8 * 1024 * 1024,
      });
      if (peer.channel == '@main') {
        peer.send({'type': 'hello', 'ready': true, 'session': 42});
        if (!mainReady.isCompleted) mainReady.complete();
      } else {
        _outputPeer = peer;
      }
      return;
    }
    if (peer.channel == '@main' && message['op'] == 'execute') {
      final source = message['source'];
      if (source == '-- output capture fixture') {
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
    }
  }

  void sendOutput(String text) {
    _outputPeer?.sendOutput(text);
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
