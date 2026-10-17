import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/orion_bridge_service.dart';
import 'package:orion/services/companion_commands.dart';
import 'package:orion/services/companion_controller.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/models/remote_script.dart';

void main() {
  late Directory storage;
  late OrionBridgeService bridge;
  late OrionController c;
  late HttpClient http;

  setUp(() async {
    storage = await Directory.systemTemp.createTemp('orion-bridge-controller-');
    bridge = OrionBridgeService(
      scriptLoader: () async => '-- bridge',
      longPollTimeout: const Duration(milliseconds: 30),
    );
    c = OrionController(storageDirectory: storage, bridgeService: bridge);
    await c.initialize();
    expect(await c.initializeBridge(port: 0), isTrue);
    http = HttpClient();
  });
  tearDown(() async {
    http.close(force: true);
    await c.closeBridge();
    c.dispose();
    await c.flushPersistence();
    await storage.delete(recursive: true);
  });
  Future<Map<String, dynamic>> request(
    String session,
    String route, {
    String transport = 'port',
    Map<String, String> values = const {},
  }) async {
    final uri =
        Uri.http('127.0.0.1:${bridge.port}', '/${transport}_bridge/$route', {
          'protocol': OrionBridgeService.protocolToken,
          'session_id': session,
          ...values,
        });
    final response = await (await http.getUrl(uri)).close();
    expect(response.statusCode, 200);
    return jsonDecode(await utf8.decodeStream(response))
        as Map<String, dynamic>;
  }

  Future<void> join(
    String session,
    String user, {
    String transport = 'port',
  }) async {
    await request(
      session,
      'hello',
      transport: transport,
      values: {
        'username': user,
        'client': 'test',
        'requested_identifier': 'User1',
      },
    );
  }

  String source(Map<String, dynamic> packet) => utf8.decode(
    base64Decode((packet['exec'] as Map)['source_b64'] as String),
  );

  test(
    'broadcast sends exact code to every transport and returns client logs',
    () async {
      await join('session-a', 'Alice');
      await join('session-b', 'Bob', transport: 'stream');
      expect(c.bridgeClients.map((v) => v.identifier), ['User1', 'User2']);
      c.execute(source: 'print("hello 🌌")', name: 'hello.luau');
      expect(c.activities.first.title, 'Script queued');
      expect(c.activities.first.detail, contains('2 clients'));
      final first = await request('session-a', 'next');
      final second = await request('session-b', 'next', transport: 'stream');
      expect(source(first), 'print("hello 🌌")');
      expect(source(second), 'print("hello 🌌")');
      expect((first['exec'] as Map)['id'], (second['exec'] as Map)['id']);
      await request(
        'session-b',
        'log',
        transport: 'stream',
        values: {
          'level': 'warn',
          'message_b64': base64Encode(utf8.encode('client output 🌌')),
        },
      );
      expect(c.activities.first.title, 'Bob · User2');
      expect(c.activities.first.detail, 'client output 🌌');
      await request(
        'session-a',
        'result',
        values: {
          'id': (first['exec'] as Map)['id'] as String,
          'ok': 'false',
          'error': 'fixture failure',
        },
      );
      expect(c.activities.first.detail, contains('fixture failure'));
    },
  );

  test(
    'display names propagate to notifications, companion snapshots and client output',
    () async {
      final joins = <String>[];
      final joined = c.bridgeClientConnected.listen(
        (client) => joins.add(client.username),
      );
      await request(
        'display-session',
        'hello',
        values: {
          'username': 'private_account_name',
          'display_name': 'Galactic Friend',
          'client': 'test',
          'requested_identifier': 'User1',
        },
      );
      expect(c.bridgeClients.single.username, 'Galactic Friend');
      expect(joins, ['Galactic Friend']);
      final state = c.exportWindowState();
      expect(jsonEncode(state), isNot(contains('private_account_name')));
      final mirror = OrionController(persistChanges: false)
        ..applyWindowState(state);
      expect(mirror.bridgeClients.single.username, 'Galactic Friend');
      await request(
        'display-session',
        'log',
        values: {'level': 'print', 'message': 'hello'},
      );
      expect(c.activities.first.title, 'Galactic Friend · User1');
      mirror.dispose();
      await joined.cancel();
    },
  );

  test(
    'hub execution sends downloaded source without replacing the editor draft',
    () async {
      await join('a', 'Alice');
      final before = c.activeDocument.toJson();
      const script = RemoteScript(
        id: 'fixture',
        provider: ScriptProvider.scriptBlox,
        title: 'Hub script',
        game: 'Fixture',
        description: '',
        externalUrl: '',
        body: 'print("exact hub source")',
      );
      await c.executeRemoteScript(script);
      expect(c.activities.first.title, 'Script queued');
      expect(source(await request('a', 'next')), script.body);
      expect(c.activeDocument.toJson(), before);
    },
  );

  test(
    'empty selection does not broadcast; each target has an independent queue',
    () async {
      await join('a', 'Alice');
      await join('b', 'Bob');
      c.setBridgeTargetAll(false);
      c.execute(source: 'print("empty")');
      expect(c.activities.first.title, 'No clients selected');
      expect((await request('a', 'next'))['exec'], isNull);
      expect((await request('b', 'next'))['exec'], isNull);
      c.setBridgeClientSelected('User2', true);
      c.execute(source: 'print("Bob only")');
      expect((await request('a', 'next'))['exec'], isNull);
      expect(source(await request('b', 'next')), 'print("Bob only")');
    },
  );

  test(
    'a reused identifier never inherits selection after disconnect',
    () async {
      await join('old-session', 'Alice');
      c.setBridgeTargetAll(false);
      c.setBridgeClientSelected('User1', true);
      c.disconnectBridgeClient('User1');
      expect(c.selectedBridgeClients, isEmpty);
      await join('new-session', 'Charlie');
      expect(c.bridgeClients.single.identifier, 'User1');
      expect(c.bridgeTargetCount, 0);
      c.execute(source: 'print("not for Charlie")');
      expect((await request('new-session', 'next'))['exec'], isNull);
    },
  );

  test(
    'deselecting an all-target row keeps the other clients selected',
    () async {
      await join('a', 'Alice');
      await join('b', 'Bob');
      c.setBridgeClientSelected('User1', false);
      expect(c.bridgeTargetAll, isFalse);
      expect(c.selectedBridgeClients, {'User2'});
    },
  );

  test(
    'companion target and execution commands share the primary bridge',
    () async {
      await join('a', 'Alice');
      await join('b', 'Bob');
      final commands = CompanionCommands(c);
      final child = CompanionController(
        initialState: c.exportWindowState(),
        sendCommand: (operation, payload, sequence) async {
          final value = await commands.apply(operation, payload);
          return {
            'envelope': {
              'ack': sequence,
              'revision': sequence,
              'state': c.exportWindowState(),
            },
            'result': value,
          };
        },
      );
      addTearDown(child.dispose);
      expect(child.bridgeClients.length, 2);
      child.setBridgeTargetAll(false);
      child.setBridgeClientSelected('User2', true);
      child.execute(source: 'print("child")', name: 'child.luau');
      await child.flushCommands();
      expect(c.selectedBridgeClients, {'User2'});
      expect((await request('a', 'next'))['exec'], isNull);
      expect(source(await request('b', 'next')), 'print("child")');
      await child.closeBridge();
      expect(c.bridgeListening, isTrue);
      child.disconnectAllBridgeClients();
      await child.flushCommands();
      expect(c.bridgeClients, isEmpty);
    },
  );

  test(
    'stale companion selection and disconnect cannot affect a replacement session',
    () async {
      await join('old-session', 'Alice');
      final commands = CompanionCommands(c);
      final child = CompanionController(
        initialState: c.exportWindowState(),
        sendCommand: (operation, payload, sequence) async {
          final result = await commands.apply(operation, payload);
          return {
            'envelope': {
              'ack': sequence,
              'revision': sequence,
              'state': c.exportWindowState(),
            },
            'result': result,
          };
        },
      );
      addTearDown(child.dispose);
      c.disconnectBridgeClient('User1');
      await join('replacement-session', 'Charlie');
      child.setBridgeClientSelected('User1', true);
      child.disconnectBridgeClient('User1');
      await child.flushCommands();
      expect(c.bridgeClients.single.username, 'Charlie');
      expect(c.selectedBridgeClients, isEmpty);
      expect(child.bridgeClients.single.username, 'Charlie');
      expect(child.selectedBridgeClients, isEmpty);
    },
  );

  test(
    'full client queues report unavailability instead of an empty selection',
    () async {
      await join('a', 'Alice');
      for (var i = 0; i < bridge.maximumQueuedPerClient; i++) {
        bridge.enqueueExecute('print($i)');
      }
      c.execute(source: 'print("queue is full")');
      expect(c.activities.first.title, 'Clients unavailable');
    },
  );

  test(
    'recovery never restores live connections or old target identifiers',
    () async {
      await join('a', 'Alice');
      c.setBridgeTargetAll(false);
      c.setBridgeClientSelected('User1', true);
      await c.flushPersistence();
      final restored = OrionController(storageDirectory: storage);
      await restored.initialize();
      expect(restored.bridgeClients, isEmpty);
      expect(restored.bridgeListening, isFalse);
      expect(restored.selectedBridgeClients, isEmpty);
      restored.dispose();
      await restored.flushPersistence();
    },
  );

  test(
    'oversized execution reports an error without crashing the editor',
    () async {
      await join('a', 'Alice');
      c.execute(source: 'x' * (bridge.maximumScriptBytes + 1));
      expect(c.activities.first.title, 'Script could not be queued');
      expect((await request('a', 'next'))['exec'], isNull);
    },
  );
}
