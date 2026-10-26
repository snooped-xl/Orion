import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/bridge_models.dart';
import 'package:orion/services/orion_bridge_service.dart';

void main() {
  late OrionBridgeService bridge;
  late HttpClient http;

  setUp(() {
    bridge = OrionBridgeService(
      scriptLoader: () => File('assets/bridge/Orion Bridge.lua').readAsString(),
      longPollTimeout: const Duration(milliseconds: 30),
    );
    http = HttpClient()..findProxy = (_) => 'DIRECT';
  });
  tearDown(() async {
    http.close(force: true);
    await bridge.close();
    bridge.dispose();
  });

  Future<({int status, dynamic data, String text, HttpHeaders headers})>
  request(
    String path, {
    String method = 'GET',
    String? session,
    Map<String, String> values = const {},
    Object? body,
    Map<String, String> headers = const {},
    bool protocol = true,
  }) async {
    final query = {
      if (protocol) 'protocol': OrionBridgeService.protocolToken,
      'session_id': ?session,
      ...values,
    };
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: bridge.port,
      path: path,
      queryParameters: query,
    );
    final req = await http.openUrl(method, uri);
    for (final entry in headers.entries) {
      req.headers.set(entry.key, entry.value);
    }
    if (body != null) {
      if (body is String) {
        req.write(body);
      } else {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
    }
    final response = await req.close();
    final text = await utf8.decoder.bind(response).join();
    dynamic data;
    try {
      data = jsonDecode(text);
    } on FormatException {
      data = null;
    }
    return (
      status: response.statusCode,
      data: data,
      text: text,
      headers: response.headers,
    );
  }

  Future<dynamic> hello(
    String session, {
    String transport = 'port',
    String username = 'Player',
    String identifier = 'User1',
  }) async {
    final response = await request(
      '/${transport}_bridge/hello',
      method: 'POST',
      body: {
        'session_id': session,
        'username': username,
        'requested_identifier': identifier,
        'client': '$transport-test',
      },
    );
    expect(response.status, 200);
    return response.data;
  }

  test(
    'construction is inert, explicit start exposes loopback status',
    () async {
      expect(bridge.listening, false);
      expect(bridge.isConnected, false);
      expect(await bridge.start(port: 0), true);
      expect(bridge.port, greaterThan(0));
      expect(bridge.listening, true);
      final result = await request('/status', protocol: false);
      expect(result.status, 200);
      expect(result.data, {
        'connected': false,
        'port_connected': false,
        'stream_connected': false,
        'compat_connected': false,
        'queued': 0,
        'clients': [],
      });
      expect(result.headers.value('access-control-allow-origin'), isNull);
      expect(result.headers.value('cache-control'), 'no-store');
    },
  );

  test(
    'all public script aliases serve the actual compatible Lua bridge',
    () async {
      await bridge.start(port: 0);
      final expected = await File(
        'assets/bridge/Orion Bridge.lua',
      ).readAsString();
      for (final path in [
        '/bridge.lua',
        '/port_bridge.lua',
        '/stream_bridge.lua',
        '/compat_bridge.lua',
        '/BRIDGE.LUA/',
      ]) {
        final response = await request(path, protocol: false);
        expect(response.status, 200);
        expect(response.text, expected);
      }
      for (final endpoint in [
        'port_bridge',
        'stream_bridge',
        'compat_bridge',
      ]) {
        expect(expected, contains('http://127.0.0.1:31337/$endpoint'));
      }
      for (final capability in [
        'orion-bridge-v2',
        'session_id',
        'requested_identifier',
        'message_b64',
        'error_b64',
        'source_b64',
        'OrionBridgeStop',
        'OrionBridgeGeneration',
        'queue_on_teleport',
        'MessageOut',
        'response.ok == true',
      ]) {
        expect(expected, contains(capability));
      }
      expect((await request('/bridge.lua', method: 'POST')).status, 405);
    },
  );

  test(
    'native executor detection honors executor and port selections',
    () async {
      await bridge.close();
      bridge.dispose();
      final mac = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final opium = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final listeners = [mac, opium];
      final subscriptions = listeners
          .map(
            (server) => server.listen((peer) {
              peer.listen((_) {}, onDone: () {}, cancelOnError: true);
            }),
          )
          .toList();
      final service = OrionBridgeService(
        macSploitMode: true,
        macSploitPorts: [mac.port],
        heliosPorts: const [],
        // Keep this isolated port outside other test default port inventories.
        opiumwarePorts: [opium.port],
      );
      addTearDown(() async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        for (final server in listeners) {
          await server.close();
        }
      });

      expect(await service.detectNativeExecutor(), 'MacSploit');
      service.setNativeExecutorPreference('opiumware');
      expect(await service.detectNativeExecutor(), 'Opiumware');
      service.setNativePortPreference(opium.port);
      expect(await service.detectNativeExecutor(), 'Opiumware');
      service.setNativeExecutorPreference('auto');
      service.setNativePortPreference(mac.port);
      expect(await service.detectNativeExecutor(), 'MacSploit');
      service.dispose();
    },
  );

  test(
    'Helios shared port is identified only from its explicit status name',
    () async {
      await bridge.close();
      bridge.dispose();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.add(jsonEncode({'op': 'status', 'name': 'Helios Mac'}));
      });
      final service = OrionBridgeService(
        macSploitMode: true,
        macSploitPorts: [server.port],
        heliosPorts: [server.port],
      );
      addTearDown(subscription.cancel);
      addTearDown(server.close);
      addTearDown(service.dispose);

      expect(await service.detectNativeExecutor(), 'Helios Mac');
      expect(service.clients.single.executorName, 'Helios Mac');
      service.dispose();
    },
  );

  test(
    'Helios detects its WebSocket port and sends execute commands',
    () async {
      await bridge.close();
      bridge.dispose();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <Map<String, dynamic>>[];
      final subscription = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.add(jsonEncode({'op': 'status', 'name': 'Helios'}));
        socket.listen((message) {
          received.add(jsonDecode(message as String) as Map<String, dynamic>);
        });
      });
      final service = OrionBridgeService(
        macSploitMode: true,
        nativeExecutorPreference: 'helios',
        heliosPorts: [server.port],
      );
      addTearDown(subscription.cancel);
      addTearDown(server.close);
      addTearDown(service.dispose);

      expect(await service.detectNativeExecutor(), 'Helios');
      expect(service.clients.single.executorName, 'Helios');
      final receipt = await service.executeNativeExecutor('print("test")');
      expect(receipt.targetIdentifiers, ['User1']);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received.single['op'], 'execute');
      expect(received.single['script'], 'print("test")');
      service.dispose();
    },
  );

  test(
    'Opiumware sends the compressed protocol payload on the selected port',
    () async {
      await bridge.close();
      bridge.dispose();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = <Socket>[];
      final received = <List<int>>[];
      final completed = Completer<void>();
      final subscription = server.listen((peer) {
        accepted.add(peer);
        final bytes = BytesBuilder(copy: false);
        peer.listen(
          bytes.add,
          onDone: () {
            received.add(bytes.takeBytes());
            if (!completed.isCompleted) completed.complete();
          },
          onError: (Object _) {
            received.add(bytes.takeBytes());
            if (!completed.isCompleted) completed.complete();
          },
          cancelOnError: true,
        );
      });
      bridge = OrionBridgeService(
        macSploitMode: true,
        opiumwarePorts: [server.port],
      );
      addTearDown(subscription.cancel);
      addTearDown(() async {
        for (final peer in accepted) {
          peer.destroy();
        }
        await server.close();
      });
      final source = 'print("opium payload")';
      final receipt = await bridge.executeOpiumware(source, port: server.port);
      expect(receipt.targetIdentifiers, ['User1']);
      await completed.future;
      expect(accepted, hasLength(1));
      expect(
        utf8.decode(ZLibCodec().decode(received.single)),
        'OpiumwareScript $source',
      );
    },
  );

  test(
    'MacSploit executes once on the first responsive port with the Rust frame format',
    () async {
      await bridge.close();
      bridge.dispose();
      final first = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final second = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final servers = [first, second]
        ..sort((left, right) => left.port.compareTo(right.port));
      final accepted = [<Socket>[], <Socket>[]];
      final received = [<List<int>>[], <List<int>>[]];
      final completed = [<Completer<void>>[], <Completer<void>>[]];
      final subscriptions = <StreamSubscription<Socket>>[];
      for (var index = 0; index < servers.length; index++) {
        final serverIndex = index;
        subscriptions.add(
          servers[index].listen((peer) {
            accepted[serverIndex].add(peer);
            final bytes = BytesBuilder(copy: false);
            final done = Completer<void>();
            completed[serverIndex].add(done);
            peer.listen(
              bytes.add,
              onDone: () {
                received[serverIndex].add(bytes.takeBytes());
                // Mimic MacSploit closing/resetting its accepted connection
                // immediately after it receives the complete execute frame.
                peer.destroy();
                if (!done.isCompleted) done.complete();
              },
              onError: (Object error) {
                received[serverIndex].add(bytes.takeBytes());
                if (!done.isCompleted) done.complete();
              },
              cancelOnError: true,
            );
          }),
        );
      }
      bridge = OrionBridgeService(
        macSploitMode: true,
        macSploitPorts: servers.map((server) => server.port),
      );
      addTearDown(() async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        for (final peers in accepted) {
          for (final peer in peers) {
            peer.destroy();
          }
        }
        await Future.wait(servers.map((server) => server.close()));
      });

      final source = 'print("héllo")';
      final receipt = await bridge.executeMacSploit(source);
      expect(receipt.targetIdentifiers, ['User1']);
      for (var attempt = 0; attempt < 50 && accepted.first.isEmpty; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(accepted.first, hasLength(1));
      await Future.wait(completed.first.map((done) => done.future));
      expect(
        accepted.last,
        isEmpty,
      ); // The second responsive instance is unused.
      expect(received.first, hasLength(1));
      final frame = Uint8List.fromList(received.first.single);
      final sourceBytes = utf8.encode(source);
      expect(frame, hasLength(16 + sourceBytes.length + 1));
      expect(frame.sublist(0, 8), List<int>.filled(8, 0));
      expect(
        ByteData.sublistView(frame).getUint32(8, Endian.little),
        sourceBytes.length + 1,
      );
      expect(utf8.decode(frame.sublist(16, frame.length - 1)), source);
      expect(frame.last, 0);

      await bridge.close();
      expect(bridge.listening, isFalse);
    },
  );

  test('MacSploit uses the full inclusive 5553–5563 port range', () {
    final service = OrionBridgeService(macSploitMode: true);
    expect(service.macSploitPorts, hasLength(11));
    expect(service.macSploitPorts.first, 5553);
    expect(service.macSploitPorts.last, 5563);
    expect(service.macSploitPorts, List.generate(11, (index) => 5553 + index));
    expect(service.nativeScanInterval, const Duration(seconds: 5));
    service.dispose();
  });

  test(
    'native executor scanner emits a single join event when a port becomes available',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = <Socket>[];
      final subscription = server.listen((peer) {
        accepted.add(peer);
        peer.listen((_) {}, onDone: () {}, cancelOnError: true);
      });
      final service = OrionBridgeService(
        macSploitMode: true,
        macSploitPorts: [server.port],
        heliosPorts: const [],
        opiumwarePorts: const [],
        nativeScanInterval: const Duration(milliseconds: 25),
      );
      final joins = <BridgeClient>[];
      final joinSubscription = service.clientConnected.listen(joins.add);
      addTearDown(joinSubscription.cancel);
      addTearDown(subscription.cancel);
      addTearDown(() async {
        for (final peer in accepted) {
          peer.destroy();
        }
        await server.close();
      });

      expect(await service.start(), isTrue);
      for (var attempt = 0; attempt < 20 && joins.isEmpty; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(joins, hasLength(1));
      expect(joins.single.executorName, 'Unknown');
      expect(joins.single.sessionId, 'macsploit:${server.port}');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(joins, hasLength(1));
      await service.close();
      service.dispose();
    },
  );

  test('MacSploit status probe detects an available configured port', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = <Socket>[];
    final subscription = server.listen((peer) {
      accepted.add(peer);
      peer.listen((_) {}, onDone: () {}, cancelOnError: true);
    });
    final service = OrionBridgeService(
      macSploitMode: true,
      macSploitPorts: [server.port],
    );
    addTearDown(subscription.cancel);
    addTearDown(() async {
      for (final peer in accepted) {
        peer.destroy();
      }
      await server.close();
    });

    expect(await service.isMacSploitRunning(), isTrue);
    service.dispose();
  });

  test(
    'MacSploit status probe returns false when ports refuse connections',
    () async {
      final unavailable = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = unavailable.port;
      await unavailable.close();
      final service = OrionBridgeService(
        macSploitMode: true,
        macSploitPorts: [port],
      );

      expect(await service.isMacSploitRunning(), isFalse);
      service.dispose();
    },
  );

  test(
    'MacSploit execution reports no instance if every probe fails',
    () async {
      await bridge.close();
      bridge.dispose();
      final unavailable = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = unavailable.port;
      await unavailable.close();
      bridge = OrionBridgeService(macSploitMode: true, macSploitPorts: [port]);
      await expectLater(
        bridge.executeMacSploit('print("offline")'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('no instance found'),
          ),
        ),
      );
      expect(bridge.clients, isEmpty);
    },
  );

  test(
    'protocol, handshake, browser origin and host checks prevent stray traffic',
    () async {
      await bridge.start(port: 0);
      expect(
        (await request('/port_bridge/hello', protocol: false)).status,
        403,
      );
      expect(
        (await request('/port_bridge/next', session: 'stray')).status,
        409,
      );
      expect(
        (await request(
          '/stream_bridge/log',
          session: 'stray',
          values: {'message': 'probe'},
        )).status,
        409,
      );
      expect(bridge.isConnected, false);
      expect(
        (await request(
          '/port_bridge/hello',
          headers: {'origin': 'https://example.com'},
        )).status,
        403,
      );
      expect(
        (await request(
          '/port_bridge/hello',
          headers: {'sec-fetch-site': 'cross-site'},
        )).status,
        403,
      );
      expect(
        (await request(
          '/port_bridge/hello',
          headers: {'host': 'example.com'},
        )).status,
        403,
      );
      expect(
        (await request(
          '/port_bridge/hello',
          protocol: false,
          headers: {
            'X-Orion-Bridge-Protocol': OrionBridgeService.protocolToken,
          },
        )).status,
        200,
      );
      expect(
        (await request('/port_bridge/hello', method: 'OPTIONS')).status,
        405,
      );
      expect((await request('/nonsense')).status, 404);
      expect((await request('/port_bridge/nonsense')).status, 404);
    },
  );

  test(
    'sessions reserve unique identifiers, sort naturally and normalize usernames',
    () async {
      await bridge.start(port: 0);
      expect(
        (await hello(
          'one',
          username: 'Alice',
          identifier: 'user01',
        ))['identifier'],
        'User1',
      );
      final second = await hello('two', username: 'Bob', transport: 'stream');
      expect(second['identifier'], 'User2');
      expect(second['reassigned'], true);
      await hello(
        'ten',
        username: 'C' * 80,
        identifier: 'User10',
        transport: 'compat',
      );
      expect(bridge.clients.map((c) => c.identifier), [
        'User1',
        'User2',
        'User10',
      ]);
      expect(bridge.clients.last.username.length, 64);
      expect(bridge.clients.first.sessionId, 'one');
      expect(() => bridge.clients.clear(), throwsUnsupportedError);
      final status = (await request('/status')).data;
      expect(status['port_connected'], true);
      expect(status['stream_connected'], true);
      expect(status['compat_connected'], true);
      expect((status['clients'] as List).length, 3);
    },
  );

  test(
    'legacy sessions remain separate for all three transport routes',
    () async {
      await bridge.start(port: 0);
      for (final transport in ['port', 'stream', 'compat']) {
        expect((await request('/${transport}_bridge/hello')).status, 200);
        expect((await request('/${transport}_bridge/ping')).status, 200);
      }
      expect(bridge.clients.length, 3);
      expect(bridge.clients.map((client) => client.sessionId).toSet(), {
        'legacy-port',
        'legacy-stream',
        'legacy-compat',
      });
    },
  );

  test(
    'targeted and broadcast executions use independent queues and base64',
    () async {
      await bridge.start(port: 0);
      await hello('one', username: 'Alice');
      await hello('two', username: 'Bob', transport: 'stream');
      final receipt = bridge.enqueueExecute(
        'print("Hello, 🌙")',
        targetIdentifiers: ['user2'],
      );
      expect(receipt.deliveredCount, 1);
      expect(receipt.targetIdentifiers, ['User2']);
      expect(() => receipt.targetIdentifiers.clear(), throwsUnsupportedError);
      expect(
        (await request('/port_bridge/next', session: 'one')).data['exec'],
        isNull,
      );
      final execution = (await request(
        '/stream_bridge/next',
        session: 'two',
      )).data['exec'];
      expect(execution['id'], receipt.id);
      expect(
        utf8.decode(base64.decode(execution['source_b64'])),
        'print("Hello, 🌙")',
      );
      expect(execution['encoding'], 'base64');
      expect(execution['origin'], 'editor');
      for (var i = 0; i < 10; i++) {
        expect(bridge.enqueueExecute('print($i)').deliveredCount, 2);
      }
      expect((await request('/status')).data['queued'], 20);
      final one =
          (await request('/port_bridge/next', session: 'one')).data['execs']
              as List;
      final two =
          (await request('/stream_bridge/next', session: 'two')).data['execs']
              as List;
      expect(one.length, 8);
      expect(one, two);
      expect((await request('/status')).data['queued'], 4);
      expect(
        ((await request('/port_bridge/next', session: 'one')).data['execs']
                as List)
            .length,
        2,
      );
      expect(
        bridge.enqueueExecute('ignored', targetIdentifiers: []).deliveredCount,
        0,
      );
    },
  );

  test('a new execution wakes an existing long poll immediately', () async {
    await bridge.close();
    bridge.dispose();
    bridge = OrionBridgeService(longPollTimeout: const Duration(seconds: 1));
    await bridge.start(port: 0);
    await hello('one');
    final pending = request('/port_bridge/next', session: 'one');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final stopwatch = Stopwatch()..start();
    bridge.enqueueExecute('print("wake")');
    expect((await pending).data['exec'], isNotNull);
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
  });

  test(
    'repeat hello is one join and transport switches preserve queued work',
    () async {
      await bridge.start(port: 0);
      final joins = <BridgeClient>[];
      final sub = bridge.clientConnected.listen(joins.add);
      await hello('one');
      await hello('one', username: 'Renamed');
      bridge.enqueueExecute('print("pending")');
      await hello('one', transport: 'compat', username: 'Renamed');
      expect(joins.length, 1);
      expect(bridge.clients.single.username, 'Renamed');
      expect(bridge.clients.single.transport, 'compat');
      expect((await request('/port_bridge/next', session: 'one')).status, 409);
      expect(
        (await request('/compat_bridge/next', session: 'one')).data['exec'],
        isNotNull,
      );
      await sub.cancel();
    },
  );

  test(
    'disconnect revokes handshake, clears stale work and wakes old polls',
    () async {
      await bridge.start(port: 0);
      await hello('one');
      bridge.enqueueExecute('old work');
      expect(bridge.disconnectClient('user1'), true);
      expect((await request('/port_bridge/next', session: 'one')).status, 409);
      await hello('one');
      expect(
        (await request('/port_bridge/next', session: 'one')).data['exec'],
        isNull,
      );
      final poll = request('/port_bridge/next', session: 'one');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      bridge.disconnectAll();
      expect((await poll).status, 409);
      expect(bridge.isConnected, false);
      expect(bridge.disconnectClient('User1'), false);
    },
  );

  test(
    'watchdog removes stale clients, queues and identifier reservations',
    () async {
      await bridge.close();
      bridge.dispose();
      bridge = OrionBridgeService(
        clientTimeout: const Duration(milliseconds: 80),
        longPollTimeout: const Duration(milliseconds: 20),
        watchdogInterval: const Duration(milliseconds: 5),
      );
      await bridge.start(port: 0);
      await hello('old');
      bridge.enqueueExecute('must not leak');
      await Future<void>.delayed(const Duration(milliseconds: 130));
      expect(bridge.isConnected, false);
      expect((await request('/status')).data['queued'], 0);
      expect(
        (await request(
          '/port_bridge/log',
          session: 'old',
          values: {'message': 'late'},
        )).status,
        409,
      );
      expect((await hello('fresh'))['identifier'], 'User1');
      expect(
        (await request('/port_bridge/next', session: 'fresh')).data['exec'],
        isNull,
      );
    },
  );

  test(
    'ping and successful long polls refresh active client heartbeats',
    () async {
      await bridge.close();
      bridge.dispose();
      bridge = OrionBridgeService(
        clientTimeout: const Duration(milliseconds: 160),
        longPollTimeout: const Duration(milliseconds: 100),
        watchdogInterval: const Duration(milliseconds: 10),
      );
      await bridge.start(port: 0);
      await hello('one');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect((await request('/port_bridge/ping', session: 'one')).status, 200);
      expect((await request('/port_bridge/next', session: 'one')).status, 200);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(bridge.isConnected, true);
    },
  );

  test(
    'console/results accept JSON, forms and GET base64 with attribution',
    () async {
      await bridge.start(port: 0);
      await hello('one');
      final events = <BridgeLogEntry>[];
      final sub = bridge.logReceived.listen(events.add);
      expect(
        (await request(
          '/port_bridge/log',
          session: 'one',
          method: 'POST',
          body: {'level': 'WARN', 'message': 'tab\tquote"unicode 🌕'},
        )).status,
        200,
      );
      await request(
        '/port_bridge/log',
        session: 'one',
        method: 'POST',
        body: 'level=print&message=hello%20form',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      );
      await request(
        '/port_bridge/log',
        session: 'one',
        values: {'message_b64': base64.encode(utf8.encode('日本語'))},
      );
      await request(
        '/port_bridge/log',
        session: 'one',
        values: {'message_b64': '!invalid!'},
      );
      await request(
        '/port_bridge/result',
        session: 'one',
        method: 'POST',
        body: {'id': 'exec_a', 'ok': true},
      );
      await request(
        '/port_bridge/result',
        session: 'one',
        values: {
          'id': 'exec_b',
          'ok': 'false',
          'error_b64': base64.encode(utf8.encode('compile error')),
        },
      );
      expect(events.map((entry) => entry.message), [
        'tab\tquote"unicode 🌕',
        'hello form',
        '日本語',
        'invalid encoded log',
        'Execution failed: compile error',
      ]);
      expect(events.first.level, 'warn');
      expect(events.last.level, 'error');
      expect(events.last.executionId, 'exec_b');
      expect(events.every((entry) => entry.identifier == 'User1'), true);
      expect(events.last.timestampUtc.isUtc, true);
      expect(
        BridgeLogEntry.fromJson(events.last.toJson()).message,
        events.last.message,
      );
      expect(
        BridgeClient.fromJson(bridge.clients.single.toJson()).sessionId,
        'one',
      );
      await sub.cancel();
      bridge.clearLogs();
      expect(bridge.logs, isEmpty);
    },
  );

  test(
    'silent successful execution results acknowledge all transports without console noise',
    () async {
      await bridge.start(port: 0);
      final events = <BridgeLogEntry>[];
      final subscription = bridge.logReceived.listen(events.add);
      addTearDown(subscription.cancel);
      for (final transport in ['port', 'stream', 'compat']) {
        final session = 'silent-$transport';
        final client = await hello(session, transport: transport);
        final receipt = bridge.enqueueExecute(
          'local silent = true',
          targetIdentifiers: [client['identifier'] as String],
        );
        final next = await request(
          '/${transport}_bridge/next',
          session: session,
        );
        expect(next.data['exec']['id'], receipt.id);
        final response = await request(
          '/${transport}_bridge/result',
          session: session,
          method: transport == 'stream' ? 'GET' : 'POST',
          values: transport == 'stream'
              ? {'id': receipt.id, 'ok': ' true '}
              : {},
          body: transport == 'port'
              ? {'id': receipt.id, 'ok': true, 'error': ''}
              : transport == 'compat'
              ? Uri(queryParameters: {'id': receipt.id, 'ok': 'true'}).query
              : null,
          headers: transport == 'compat'
              ? {'content-type': 'application/x-www-form-urlencoded'}
              : {},
        );
        expect(response.status, 200);
        expect(response.data, {'ok': true});
        expect(
          bridge.clients.every((client) => client.pendingCount == 0),
          isTrue,
        );
        expect(bridge.logs, isEmpty);
        expect(events, isEmpty);
      }
      // Legacy successful results without an execution ID are silent as well.
      expect(
        (await request(
          '/port_bridge/result',
          session: 'silent-port',
          values: {'ok': 'true'},
        )).data,
        {'ok': true},
      );
      expect(bridge.logs, isEmpty);
      expect(events, isEmpty);
    },
  );

  test(
    'successful results preserve the exact mirrored print, warning and error stream',
    () async {
      await bridge.start(port: 0);
      await hello('console');
      final events = <BridgeLogEntry>[];
      final subscription = bridge.logReceived.listen(events.add);
      addTearDown(subscription.cancel);
      final expected = [
        ('print', 'hello world'),
        ('warn', '  exact warning\t🌕\n'),
        ('error', 'client error: line 12'),
      ];
      for (final message in expected) {
        await request(
          '/port_bridge/log',
          session: 'console',
          method: 'POST',
          body: {'level': message.$1, 'message': message.$2},
        );
        final response = await request(
          '/port_bridge/result',
          session: 'console',
          values: {'id': 'exec_${message.$1}', 'ok': 'true'},
        );
        expect(response.data, {'ok': true});
      }
      expect(events.map((entry) => (entry.level, entry.message)), expected);
      expect(
        bridge.logs.map((entry) => (entry.level, entry.message)),
        expected,
      );
      expect(events.every((entry) => entry.executionId == null), isTrue);
    },
  );

  test(
    'failed acknowledgements stay visible without IDs and avoid an obvious mirrored duplicate',
    () async {
      await bridge.start(port: 0);
      await hello('failed');
      const id = 'exec_a40bf9e87ef249f5b041d7d1e3d5d2cb';
      final failure = await request(
        '/port_bridge/result',
        session: 'failed',
        method: 'POST',
        body: {'id': id, 'ok': false, 'error': 'syntax error'},
      );
      expect(failure.data, {'ok': true});
      expect(bridge.logs.single.message, 'Execution failed: syntax error');
      expect(bridge.logs.single.message, isNot(contains(id)));
      expect(bridge.logs.single.level, 'error');
      expect(bridge.logs.single.executionId, id);
      await request(
        '/port_bridge/result',
        session: 'failed',
        values: {'id': 'empty-error', 'ok': 'false', 'error': ''},
      );
      expect(bridge.logs.last.message, 'Execution failed: unknown error');
      for (var i = 0; i < 2; i++) {
        await request(
          '/port_bridge/log',
          session: 'failed',
          method: 'POST',
          body: {'level': 'error', 'message': 'runtime failure'},
        );
      }
      await request(
        '/port_bridge/result',
        session: 'failed',
        values: {
          'id': 'mirrored-failure',
          'ok': 'false',
          'error': 'runtime failure',
        },
      );
      expect(bridge.logs.map((entry) => entry.message), [
        'Execution failed: syntax error',
        'Execution failed: unknown error',
        'runtime failure',
        'runtime failure',
      ]);
      // Another client's matching error must still be surfaced and attributed.
      await hello('other-failed');
      await request(
        '/port_bridge/result',
        session: 'other-failed',
        values: {
          'id': 'other-failure',
          'ok': 'false',
          'error': 'runtime failure',
        },
      );
      expect(bridge.logs.last.message, 'Execution failed: runtime failure');
      expect(bridge.logs.last.identifier, 'User2');
    },
  );

  test(
    'a replacement client reusing an identifier keeps its matching execution failure',
    () async {
      await bridge.start(port: 0);
      await hello('old-player');
      await request(
        '/port_bridge/log',
        session: 'old-player',
        method: 'POST',
        body: {'level': 'error', 'message': 'same error'},
      );
      bridge.disconnectAll();
      await hello('replacement-player');
      await request(
        '/port_bridge/result',
        session: 'replacement-player',
        values: {
          'id': 'replacement-execution',
          'ok': 'false',
          'error': 'same error',
        },
      );
      expect(bridge.logs.map((entry) => entry.message), [
        'same error',
        'Execution failed: same error',
      ]);
      expect(bridge.logs.every((entry) => entry.identifier == 'User1'), isTrue);
    },
  );

  test(
    'resource limits bound requests, sessions, queues, scripts and logs',
    () async {
      await bridge.close();
      bridge.dispose();
      bridge = OrionBridgeService(
        maximumClients: 2,
        maximumQueuedPerClient: 2,
        maximumRememberedLogs: 3,
        maximumLogLength: 16,
        maximumScriptBytes: 32,
        maximumRequestBytes: 512,
        longPollTimeout: const Duration(milliseconds: 10),
      );
      await bridge.start(port: 0);
      await hello('one');
      await hello('two');
      expect(
        (await request(
          '/port_bridge/hello',
          values: {'session_id': 'three'},
        )).status,
        429,
      );
      expect(bridge.enqueueExecute('a').deliveredCount, 2);
      expect(bridge.enqueueExecute('b').deliveredCount, 2);
      expect(bridge.enqueueExecute('c').deliveredCount, 0);
      expect((await request('/status')).data['queued'], 4);
      expect(() => bridge.enqueueExecute('x' * 33), throwsArgumentError);
      expect(
        (await request(
          '/port_bridge/log',
          session: 'one',
          method: 'POST',
          body: {'message': 'x' * 600},
        )).status,
        413,
      );
      for (var i = 0; i < 4; i++) {
        await request(
          '/port_bridge/log',
          session: 'one',
          values: {'message': '$i${'z' * 50}'},
        );
      }
      expect(bridge.logs.length, 3);
      expect(bridge.logs.first.message, '1${'z' * 15}');
      expect(bridge.logs.last.message.length, 16);
    },
  );

  test(
    'malformed JSON, values and session ids cannot create connections',
    () async {
      await bridge.start(port: 0);
      expect(
        (await request(
          '/port_bridge/hello',
          method: 'POST',
          body: '{broken',
          headers: {'content-type': 'application/json'},
        )).status,
        400,
      );
      expect(
        (await request(
          '/port_bridge/hello',
          method: 'POST',
          body: {
            'username': ['nested'],
          },
        )).status,
        400,
      );
      expect(
        (await request('/port_bridge/hello', session: 'with spaces')).status,
        400,
      );
      expect(
        (await request('/port_bridge/hello', session: 'x' * 129)).status,
        400,
      );
      expect(bridge.isConnected, false);
      expect(bridge.logs, isEmpty);
    },
  );

  test(
    'repeated start, binding failure, close and restart remain usable',
    () async {
      expect(await bridge.start(port: 0), true);
      final firstPort = bridge.port;
      expect(await bridge.start(port: firstPort), true);
      expect(bridge.port, firstPort);
      final other = OrionBridgeService();
      expect(await other.start(port: firstPort), false);
      expect(other.error, contains('could not listen'));
      expect(other.logs.last.level, 'error');
      other.dispose();
      await hello('one');
      await bridge.close();
      http.close(force: true);
      http = HttpClient()..findProxy = (_) => 'DIRECT';
      expect(bridge.listening, false);
      expect(bridge.clients, isEmpty);
      expect(await bridge.start(port: firstPort), true);
      expect((await request('/status')).status, 200);
    },
  );
  test(
    'global queue byte budget is released by delivery and disconnect',
    () async {
      await bridge.close();
      bridge.dispose();
      bridge = OrionBridgeService(
        maximumQueuedBytes: 6,
        longPollTimeout: const Duration(milliseconds: 10),
      );
      await bridge.start(port: 0);
      await hello('one');
      await hello('two');
      expect(bridge.enqueueExecute('éé').targetIdentifiers, ['User1']);
      expect((await request('/status')).data['queued'], 1);
      expect(
        (await request('/port_bridge/next', session: 'one')).data['exec'],
        isNotNull,
      );
      expect(
        bridge
            .enqueueExecute('hello', targetIdentifiers: ['User2'])
            .deliveredCount,
        1,
      );
      bridge.disconnectClient('User2');
      expect(
        bridge
            .enqueueExecute('hello', targetIdentifiers: ['User1'])
            .deliveredCount,
        1,
      );
    },
  );

  test(
    'transport changes wake old poll without stealing the new transport work',
    () async {
      await bridge.close();
      bridge.dispose();
      bridge = OrionBridgeService(longPollTimeout: const Duration(seconds: 1));
      await bridge.start(port: 0);
      await hello('one');
      final oldPoll = request('/port_bridge/next', session: 'one');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await hello('one', transport: 'stream');
      bridge.enqueueExecute('new transport');
      expect((await oldPoll).status, 409);
      expect(
        (await request('/stream_bridge/next', session: 'one')).data['exec'],
        isNotNull,
      );
    },
  );

  test(
    'disconnect and immediate same-session reconnect cannot revive the old poll',
    () async {
      await bridge.close();
      bridge.dispose();
      bridge = OrionBridgeService(longPollTimeout: const Duration(seconds: 1));
      await bridge.start(port: 0);
      await hello('one');
      final oldPoll = request('/port_bridge/next', session: 'one');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      bridge.disconnectAll();
      await hello('one');
      bridge.enqueueExecute('fresh session work');
      expect((await oldPoll).status, 409);
      expect(
        (await request('/port_bridge/next', session: 'one')).data['exec'],
        isNotNull,
      );
    },
  );

  test(
    'missing bundled script responds cleanly without connecting a client',
    () async {
      await bridge.close();
      bridge.dispose();
      bridge = OrionBridgeService(
        scriptLoader: () async =>
            throw const FileSystemException('missing asset'),
      );
      await bridge.start(port: 0);
      expect((await request('/bridge.lua', protocol: false)).status, 404);
      expect(bridge.isConnected, false);
    },
  );
  test(
    'slow chunked request has a total body deadline rather than per-chunk timeout',
    () async {
      await bridge.close();
      bridge.dispose();
      bridge = OrionBridgeService(
        requestTimeout: const Duration(milliseconds: 100),
      );
      await bridge.start(port: 0);
      final socket = await Socket.connect('127.0.0.1', bridge.port);
      final response = utf8.decoder.bind(socket).join();
      socket.write(
        'POST /port_bridge/hello?protocol=orion-bridge-v2 HTTP/1.1\r\nHost: 127.0.0.1:${bridge.port}\r\nTransfer-Encoding: chunked\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n',
      );
      socket.write('1\r\n{\r\n');
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      socket.write('1\r\n"\r\n');
      await socket.flush();
      try {
        final text = await response.timeout(const Duration(seconds: 2));
        // Cancelling an unfinished HttpRequest may close its socket before
        // Dart can send 408; either result terminates the stalled upload.
        expect(text.isEmpty || text.contains('408 Request Timeout'), true);
        expect(bridge.isConnected, false);
      } finally {
        socket.destroy();
      }
    },
  );
  test(
    'executor metadata comes from JSON, GET and form hello on every transport',
    () async {
      await bridge.start(port: 0);
      final joins = <BridgeClient>[];
      final subscription = bridge.clientConnected.listen(joins.add);
      final jsonHello = await request(
        '/port_bridge/hello',
        method: 'POST',
        body: {
          'session_id': 'json-executor',
          'username': 'Alice',
          'client': 'port-bridge',
          'executor_name': 'Example Engine',
        },
      );
      expect(jsonHello.status, 200);
      expect(jsonHello.data['executorName'], 'Example Engine');
      final getHello = await request(
        '/stream_bridge/hello',
        session: 'get-executor',
        values: {
          'username': 'Bob',
          'client': 'stream-bridge',
          'executor_name': 'Another Engine',
        },
      );
      expect(getHello.status, 200);
      final formHello = await request(
        '/compat_bridge/hello',
        method: 'POST',
        body:
            'session_id=form-executor&username=Carol&client=compat-bridge&executor_name=Third%20Engine',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      );
      expect(formHello.status, 200);
      expect(bridge.clients.map((c) => c.executorName), [
        'Example Engine',
        'Another Engine',
        'Third Engine',
      ]);
      expect(bridge.clients.map((c) => c.clientLabel), [
        'port-bridge',
        'stream-bridge',
        'compat-bridge',
      ]);
      expect(joins.map((c) => c.executorName), [
        'Example Engine',
        'Another Engine',
        'Third Engine',
      ]);
      final clients = (await request('/status')).data['clients'] as List;
      expect(clients.map((dynamic c) => c['executorName']), [
        'Example Engine',
        'Another Engine',
        'Third Engine',
      ]);
      await subscription.cancel();
    },
  );

  test(
    'executor name is sanitized and bounded without changing transport labels',
    () async {
      await bridge.start(port: 0);
      await request(
        '/port_bridge/hello',
        method: 'POST',
        body: {
          'session_id': 'controls',
          'executor_name': '  Example\u0000 Engine\n\t  ',
          'client': 'port-bridge',
        },
      );
      expect(bridge.clients.single.executorName, 'Example Engine');
      expect(bridge.clients.single.transport, 'port');
      await request(
        '/stream_bridge/hello',
        session: 'long-name',
        values: {'executor_name': 'É' * 100},
      );
      expect(bridge.clients.last.executorName, 'É' * 64);
      await request(
        '/compat_bridge/hello',
        method: 'POST',
        body:
            'session_id=empty-name&executor_name=%20%09%0A%20&client=compat-bridge',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      );
      expect(bridge.clients.last.executorName, isEmpty);
    },
  );

  test(
    'legacy hello keeps executor blank and cannot infer it from its client label',
    () async {
      await bridge.start(port: 0);
      for (final transport in ['port', 'stream', 'compat']) {
        await hello('legacy-$transport', transport: transport);
      }
      expect(bridge.clients.every((c) => c.executorName.isEmpty), true);
      expect(bridge.clients.map((c) => c.clientLabel), [
        'port-test',
        'stream-test',
        'compat-test',
      ]);
    },
  );

  test(
    'older hello refresh preserves known executor and explicit updates replace it',
    () async {
      await bridge.start(port: 0);
      final joins = <BridgeClient>[];
      final subscription = bridge.clientConnected.listen(joins.add);
      await request(
        '/port_bridge/hello',
        method: 'POST',
        body: {
          'session_id': 'same-session',
          'executor_name': 'Original Engine',
          'username': 'Alice',
        },
      );
      await hello('same-session', transport: 'stream', username: 'Alice');
      expect(bridge.clients.single.executorName, 'Original Engine');
      expect(bridge.clients.single.transport, 'stream');
      await request(
        '/compat_bridge/hello',
        session: 'same-session',
        values: {'executor_name': 'Updated Engine'},
      );
      expect(bridge.clients.single.executorName, 'Updated Engine');
      expect(joins.length, 1);
      final serialized = bridge.clients.single.toJson();
      expect(serialized['executorName'], 'Updated Engine');
      expect(BridgeClient.fromJson(serialized).executorName, 'Updated Engine');
      await request(
        '/compat_bridge/hello',
        session: 'same-session',
        values: {'executor_name': ''},
      );
      expect(bridge.clients.single.executorName, isEmpty);
      await subscription.cancel();
    },
  );

  test(
    'older snapshots default to blank executor and new snapshots sanitize metadata',
    () {
      final old = BridgeClient.fromJson({
        'identifier': 'User1',
        'username': 'Alice',
        'transport': 'port',
        'clientLabel': 'port-bridge',
      });
      expect(old.executorName, isEmpty);
      expect(old.toJson()['executorName'], isEmpty);
      expect(
        BridgeClient.fromJson({
          ...old.toJson(),
          'executorName': null,
        }).executorName,
        isEmpty,
      );
      expect(
        BridgeClient.fromJson({
          ...old.toJson(),
          'executorName': {'unexpected': 'map'},
        }).executorName,
        isEmpty,
      );
      expect(
        BridgeClient.fromJson({
          ...old.toJson(),
          'executorName': '  Real\n Engine\u0000  ',
        }).executorName,
        'Real Engine',
      );
      expect(
        BridgeClient.fromJson({
          ...old.toJson(),
          'executorName': 'X' * 100,
        }).executorName.length,
        64,
      );
    },
  );

  test(
    'Lua hello reports detected executor name while retaining version in game console',
    () async {
      final source = await File(
        'assets/bridge/Orion Bridge.lua',
      ).readAsString();
      expect(
        source.indexOf('local executor_name = resolve_executor_name()'),
        lessThan(source.indexOf('local function send_hello')),
      );
      expect(
        source,
        contains('return identifyexecutor and identifyexecutor()'),
      );
      expect(source, contains('or getexecutorname and getexecutorname()'));
      expect(
        source,
        contains('.. ",\\"executor_name\\":" .. json_string(executor_name)'),
      );
      expect(
        source,
        contains('.. "&executor_name=" .. url_encode(executor_name)'),
      );
      expect(
        source,
        contains(
          'print("Executor Version: " .. tostring(version or "Unknown"))',
        ),
      );
      expect(source, isNot(contains('executor_version')));
    },
  );
  test(
    'close waits for an in-flight startup before an immediate restart',
    () async {
      final starting = bridge.start(port: 0);
      await bridge.close();
      expect(await starting, false);
      expect(await bridge.start(port: 0), true);
      expect(bridge.listening, true);
      expect((await request('/status')).status, 200);
    },
  );

  test(
    'display_name overrides account username across JSON, query and form hello',
    () async {
      await bridge.start(port: 0);
      final jsonHello = await request(
        '/port_bridge/hello',
        method: 'POST',
        body: {
          'session_id': 'display-json',
          'username': 'account_codename',
          'display_name': '  Alice Blue  ',
        },
      );
      expect(jsonHello.data['username'], 'Alice Blue');
      final getHello = await request(
        '/stream_bridge/hello',
        session: 'display-get',
        values: {'username': 'another_account', 'display_name': 'Béla'},
      );
      expect(getHello.data['username'], 'Béla');
      final formHello = await request(
        '/compat_bridge/hello',
        method: 'POST',
        body:
            'session_id=display-form&username=third_account&display_name=Carol%20Sky',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      );
      expect(formHello.data['username'], 'Carol Sky');
      expect(bridge.clients.map((c) => c.username), [
        'Alice Blue',
        'Béla',
        'Carol Sky',
      ]);
      expect(
        ((await request('/status')).data['clients'] as List).map(
          (dynamic c) => c['username'],
        ),
        ['Alice Blue', 'Béla', 'Carol Sky'],
      );
    },
  );

  test(
    'empty display_name keeps backward-compatible username fallback',
    () async {
      await bridge.start(port: 0);
      final result = await request(
        '/port_bridge/hello',
        method: 'POST',
        body: {
          'session_id': 'legacy-display',
          'username': 'Legacy Player',
          'display_name': '  \n\t  ',
        },
      );
      expect(result.data['username'], 'Legacy Player');
      await request(
        '/port_bridge/hello',
        method: 'POST',
        body: {
          'session_id': 'legacy-display',
          'username': 'legacy_account',
          'display_name': '  New\u0000 Display\n  ',
        },
      );
      expect(bridge.clients.single.username, 'New Display');
    },
  );
  test(
    'retried result is acknowledged once per session across POST, GET and reconnect',
    () async {
      await bridge.start(port: 0);
      await hello('result-retry');
      for (var i = 0; i < 2; i++) {
        final response = await request(
          '/port_bridge/result',
          method: i == 0 ? 'POST' : 'GET',
          session: 'result-retry',
          body: i == 0
              ? {'id': 'same-execution', 'ok': false, 'error': 'failed once'}
              : null,
          values: i == 0
              ? {}
              : {
                  'id': 'same-execution',
                  'ok': 'false',
                  'error_b64': base64.encode(utf8.encode('failed once')),
                },
        );
        expect(response.status, 200);
        expect(response.data['ok'], true);
      }
      expect(bridge.logs.length, 1);
      expect(bridge.logs.single.message, contains('failed once'));
      bridge.disconnectAll();
      await hello('result-retry', transport: 'stream');
      expect(
        (await request(
          '/stream_bridge/result',
          session: 'result-retry',
          values: {'id': 'same-execution', 'ok': 'false'},
        )).status,
        200,
      );
      expect(bridge.logs.length, 1);
      await hello('other-player', transport: 'compat');
      await request(
        '/compat_bridge/result',
        session: 'other-player',
        values: {
          'id': 'same-execution',
          'ok': 'false',
          'error': 'other client',
        },
      );
      expect(bridge.logs.length, 2);
      expect(bridge.logs.last.identifier, 'User2');
    },
  );

  test(
    'result deduplication is bounded and does not hide legacy unlabelled results',
    () async {
      await bridge.close();
      bridge.dispose();
      bridge = OrionBridgeService(maximumRememberedResults: 2);
      await bridge.start(port: 0);
      await hello('result-budget');
      for (final id in ['first', 'second', 'second', 'third', 'second']) {
        await request(
          '/port_bridge/result',
          session: 'result-budget',
          values: {'id': id, 'ok': ' false ', 'error': 'failed $id'},
        );
      }
      expect(bridge.logs.length, 3);
      expect(bridge.logs.every((entry) => entry.level == 'error'), true);
      await request(
        '/port_bridge/result',
        session: 'result-budget',
        values: {'id': 'first', 'ok': 'false', 'error': 'failed first'},
      );
      expect(bridge.logs.length, 4);
      for (var i = 0; i < 2; i++) {
        await request(
          '/port_bridge/result',
          session: 'result-budget',
          values: {'ok': 'false', 'error': 'legacy'},
        );
      }
      expect(bridge.logs.length, 6);
    },
  );
  test(
    'replacing Lua generation revokes its old poll without dropping queued work or rejoining',
    () async {
      await bridge.close();
      bridge.dispose();
      bridge = OrionBridgeService(longPollTimeout: const Duration(seconds: 1));
      await bridge.start(port: 0);
      final joins = <BridgeClient>[];
      final subscription = bridge.clientConnected.listen(joins.add);
      await request(
        '/port_bridge/hello',
        session: 'same-player',
        values: {'bridge_generation': '1', 'username': 'Player'},
      );
      final oldPoll = request(
        '/port_bridge/next',
        session: 'same-player',
        values: {'bridge_generation': '1'},
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await request(
        '/port_bridge/hello',
        session: 'same-player',
        values: {'bridge_generation': '2', 'username': 'Player'},
      );
      final receipt = bridge.enqueueExecute(
        'print("replacement receives this")',
      );
      expect((await oldPoll).status, 409);
      final currentPoll = await request(
        '/port_bridge/next',
        session: 'same-player',
        values: {'bridge_generation': '2'},
      );
      expect(currentPoll.status, 200);
      expect(currentPoll.data['exec']['id'], receipt.id);
      expect(joins.length, 1);
      expect(bridge.clients.single.identifier, 'User1');
      expect(bridge.clients.single.sessionId, 'same-player');
      bridge.enqueueExecute('already queued');
      await request(
        '/port_bridge/hello',
        session: 'same-player',
        values: {'bridge_generation': '3'},
      );
      expect(
        (await request(
          '/port_bridge/next',
          session: 'same-player',
          values: {'bridge_generation': '3'},
        )).data['exec'],
        isNotNull,
      );
      await subscription.cancel();
    },
  );

  test(
    'periodic and older hellos preserve the current poll generation',
    () async {
      await bridge.close();
      bridge.dispose();
      bridge = OrionBridgeService(longPollTimeout: const Duration(seconds: 1));
      await bridge.start(port: 0);
      await request(
        '/port_bridge/hello',
        session: 'same-player',
        values: {'bridge_generation': '3'},
      );
      final poll = request(
        '/port_bridge/next',
        session: 'same-player',
        values: {'bridge_generation': '3'},
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await request(
        '/port_bridge/hello',
        session: 'same-player',
        values: {'bridge_generation': '3'},
      );
      await hello('same-player');
      final receipt = bridge.enqueueExecute('not cancelled by heartbeat hello');
      final result = await poll;
      expect(result.status, 200);
      expect(result.data['exec']['id'], receipt.id);
    },
  );

  test(
    'late result body cannot report against a disconnected and replaced session',
    () async {
      await bridge.start(port: 0);
      await hello('same-player', username: 'Earlier Player');
      final socket = await Socket.connect('127.0.0.1', bridge.port);
      final response = utf8.decoder.bind(socket).join();
      socket.write(
        'POST /port_bridge/result?protocol=orion-bridge-v2&session_id=same-player HTTP/1.1\r\nHost: 127.0.0.1:${bridge.port}\r\nTransfer-Encoding: chunked\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n',
      );
      const beginning = '{"id":"late-result",';
      socket.write(
        '''${beginning.length.toRadixString(16)}\r\n$beginning\r\n''',
      );
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      bridge.disconnectAll();
      await hello('same-player', username: 'Replacement Player');
      const ending = '"ok":true}';
      socket.write(
        '''${ending.length.toRadixString(16)}\r\n$ending\r\n0\r\n\r\n''',
      );
      await socket.flush();
      try {
        expect(
          await response.timeout(const Duration(seconds: 2)),
          contains('409 Conflict'),
        );
        expect(bridge.logs, isEmpty);
        expect(bridge.clients.single.username, 'Replacement Player');
      } finally {
        socket.destroy();
      }
    },
  );
  test(
    'stale requests arriving after replacement hello cannot poll, log, result or ping',
    () async {
      await bridge.start(port: 0);
      await request(
        '/port_bridge/hello',
        session: 'same-player',
        values: {'bridge_generation': '1'},
      );
      await request(
        '/port_bridge/hello',
        session: 'same-player',
        values: {'bridge_generation': '2'},
      );
      final receipt = bridge.enqueueExecute('new generation only');
      for (final endpoint in ['next', 'log', 'result', 'ping']) {
        final response = await request(
          '/port_bridge/$endpoint',
          session: 'same-player',
          values: {
            'bridge_generation': '1',
            'message': 'must not log',
            'id': 'must-not-report',
            'ok': 'true',
          },
        );
        expect(response.status, 409, reason: endpoint);
      }
      expect(bridge.logs, isEmpty);
      expect((await request('/status')).data['queued'], 1);
      final valid = await request(
        '/port_bridge/next',
        session: 'same-player',
        values: {'bridge_generation': '2'},
      );
      expect(valid.data['exec']['id'], receipt.id);
      expect(
        (await request('/port_bridge/ping', session: 'same-player')).status,
        409,
      );
    },
  );

  test(
    'delayed older hello cannot roll back a numeric generation or display metadata',
    () async {
      await bridge.start(port: 0);
      await request(
        '/port_bridge/hello',
        session: 'same-player',
        values: {
          'bridge_generation': '0002',
          'display_name': 'Current Display',
        },
      );
      final old = await request(
        '/port_bridge/hello',
        session: 'same-player',
        values: {'bridge_generation': '1', 'display_name': 'Old Display'},
      );
      expect(old.status, 409);
      expect(bridge.clients.single.displayName, 'Current Display');
      expect(
        (await request(
          '/port_bridge/ping',
          session: 'same-player',
          values: {'bridge_generation': '2'},
        )).status,
        200,
      );
      expect(
        (await request(
          '/port_bridge/hello',
          session: 'same-player',
          values: {'bridge_generation': '2', 'display_name': 'Still Current'},
        )).status,
        200,
      );
      expect(bridge.clients.single.displayName, 'Still Current');
    },
  );

  test(
    'generation tokens are bounded and opaque tags retain compatibility',
    () async {
      await bridge.start(port: 0);
      for (final tag in ['', 'has space', 'x' * 65]) {
        expect(
          (await request(
            '/port_bridge/hello',
            session: 'invalid-token',
            values: {'bridge_generation': tag},
          )).status,
          400,
        );
      }
      expect(bridge.clients, isEmpty);
      expect(
        (await request(
          '/port_bridge/hello',
          session: 'opaque-token',
          values: {'bridge_generation': 'instance-v2:ab.cd'},
        )).status,
        200,
      );
      expect(
        (await request(
          '/port_bridge/ping',
          session: 'opaque-token',
          values: {'bridge_generation': 'instance-v2:ab.cd'},
        )).status,
        200,
      );
      expect(
        (await request(
          '/port_bridge/ping',
          session: 'opaque-token',
          values: {'bridge_generation': 'other-instance'},
        )).status,
        409,
      );
      expect(
        (await request(
          '/port_bridge/hello',
          session: 'opaque-token',
          values: {'bridge_generation': 'new-instance'},
        )).status,
        200,
      );
    },
  );

  test(
    'result generation is rechecked after an in-flight request body completes',
    () async {
      await bridge.start(port: 0);
      await request(
        '/port_bridge/hello',
        session: 'same-player',
        values: {'bridge_generation': '1'},
      );
      final socket = await Socket.connect('127.0.0.1', bridge.port);
      final response = utf8.decoder.bind(socket).join();
      socket.write(
        'POST /port_bridge/result?protocol=orion-bridge-v2&session_id=same-player&bridge_generation=1 HTTP/1.1\r\nHost: 127.0.0.1:${bridge.port}\r\nTransfer-Encoding: chunked\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n',
      );
      const beginning = '{"id":"late-generation-result",';
      socket.write(
        '''${beginning.length.toRadixString(16)}\r\n$beginning\r\n''',
      );
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await request(
        '/port_bridge/hello',
        session: 'same-player',
        values: {'bridge_generation': '2'},
      );
      const ending = '"ok":true}';
      socket.write(
        '''${ending.length.toRadixString(16)}\r\n$ending\r\n0\r\n\r\n''',
      );
      await socket.flush();
      try {
        expect(
          await response.timeout(const Duration(seconds: 2)),
          contains('409 Conflict'),
        );
        expect(bridge.logs, isEmpty);
      } finally {
        socket.destroy();
      }
    },
  );
  test(
    'upgrading an untagged bridge invalidates its waiting and late polls',
    () async {
      await bridge.close();
      bridge.dispose();
      bridge = OrionBridgeService(longPollTimeout: const Duration(seconds: 1));
      await bridge.start(port: 0);
      await hello('same-player');
      final legacyPoll = request('/port_bridge/next', session: 'same-player');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await request(
        '/port_bridge/hello',
        session: 'same-player',
        values: {'bridge_generation': '1'},
      );
      final receipt = bridge.enqueueExecute('upgraded bridge only');
      expect((await legacyPoll).status, 409);
      for (final endpoint in ['next', 'log', 'result', 'ping']) {
        expect(
          (await request(
            '/port_bridge/$endpoint',
            session: 'same-player',
            values: {'message': 'old', 'id': 'old', 'ok': 'true'},
          )).status,
          409,
          reason: endpoint,
        );
      }
      final currentPoll = await request(
        '/port_bridge/next',
        session: 'same-player',
        values: {'bridge_generation': '1'},
      );
      expect(currentPoll.data['exec']['id'], receipt.id);
      expect(bridge.logs, isEmpty);
      expect(bridge.clients.length, 1);
    },
  );
}
