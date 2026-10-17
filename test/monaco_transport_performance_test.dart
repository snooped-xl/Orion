import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/monaco_editor_service.dart';

class _Assets extends EditorAssetServer {
  @override
  Future<Uri> start() async =>
      Uri.parse('http://127.0.0.1:9999/editor/index.html');

  @override
  Future<void> close() async {}
}

class _Transport extends MethodChannel {
  _Transport() : super('orion/transport-performance-test');

  Future<dynamic> Function(MethodCall)? handler;
  final calls = <MethodCall>[];
  final commands = <Map<String, dynamic>>[];
  Completer<void>? themeGate;
  Completer<void>? themeEntered;
  Completer<void>? sendGate;
  Completer<void>? sendEntered;
  bool failSend = false;

  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall)? callback) {
    handler = callback;
  }

  Future<void> message(Map<String, Object?> value) async {
    await handler?.call(MethodCall('message', jsonEncode(value)));
  }

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    calls.add(MethodCall(method, arguments));
    if (method == 'create') await message({'type': 'ready'});
    if (method == 'setTheme' && themeGate != null) {
      if (!(themeEntered?.isCompleted ?? true)) themeEntered!.complete();
      await themeGate!.future;
    }
    if (method == 'send') {
      if (failSend) throw PlatformException(code: 'send_failed');
      commands.add(jsonDecode(arguments as String) as Map<String, dynamic>);
      if (!(sendEntered?.isCompleted ?? true)) sendEntered!.complete();
      await sendGate?.future;
    }
    return null;
  }
}

Map<String, Object?> _snapshot({
  String content = 'print("original")',
  String name = 'untitled.lua',
  bool dirty = false,
  String brightness = 'dark',
  String accent = '#88b5ff',
}) => {
  'documents': [
    {'id': 'a', 'name': name, 'content': content, 'dirty': dirty},
    {'id': 'b', 'name': 'saved.lua', 'content': '-- another model'},
  ],
  'activeId': 'a',
  'options': {
    'brightness': brightness,
    'fontSize': 14,
    'wordWrap': true,
    'windowBackdrop': {
      'gradient': {
        'colors': ['#102030', accent],
        'stops': [0.0, 1.0],
      },
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Transport transport;
  late MonacoEditorService service;
  late List<(String, String)> changes;

  setUp(() async {
    transport = _Transport();
    changes = [];
    service = MonacoEditorService(
      channel: transport,
      server: _Assets(),
      onChange: (id, content) => changes.add((id, content)),
      onShortcut: (_) {},
    );
    await service.synchronize(_snapshot());
    await service.initialize();
    expect(service.ready, true);
    expect(transport.commands, hasLength(1));
  });

  tearDown(() {
    service.dispose();
  });

  test(
    'native edits and repeated acknowledgements do not resend large models',
    () async {
      final source = List.filled(
        4000,
        'local player = game.Players.LocalPlayer',
      ).join('\n');
      await service.synchronize(_snapshot(content: source));
      final before = transport.commands.length;
      final initialCalls = transport.calls.length;
      for (var index = 0; index < 100; index++) {
        final edited = '$source\n-- keystroke $index';
        await transport.message({
          'type': 'change',
          'id': 'a',
          'content': edited,
        });
        await service.synchronize(_snapshot(content: edited));
        await service.synchronize(_snapshot(content: edited));
      }
      expect(changes, hasLength(100));
      expect(changes.last, ('a', '$source\n-- keystroke 99'));
      expect(transport.commands, hasLength(before));
      expect(
        transport.calls
            .skip(initialCalls)
            .where((call) => call.method == 'send'),
        isEmpty,
      );
    },
  );

  test(
    'external replacement and reverting to the first source both reach Monaco',
    () async {
      await transport.message({
        'type': 'change',
        'id': 'a',
        'content': 'print("typed")',
      });
      await service.synchronize(_snapshot(content: 'print("typed")'));
      expect(transport.commands, hasLength(1));

      await service.synchronize(_snapshot(content: 'print("opened file")'));
      final replacement = (transport.commands.last['documents'] as List).first;
      expect(replacement['content'], 'print("opened file")');
      expect(replacement['nativeEcho'], isNot(true));
      await service.synchronize(_snapshot());
      final original = (transport.commands.last['documents'] as List).first;
      expect(original['content'], 'print("original")');
      expect(original['nativeEcho'], isNot(true));
      expect(transport.commands, hasLength(3));
    },
  );

  test(
    'metadata, nested theme changes and model selection still synchronize',
    () async {
      await service.synchronize(_snapshot(name: 'renamed.luau', dirty: true));
      expect(transport.commands, hasLength(2));
      expect(
        (transport.commands.last['documents'] as List).first['name'],
        'renamed.luau',
      );
      await service.synchronize(
        _snapshot(name: 'renamed.luau', dirty: true, accent: '#aaccff'),
      );
      expect(transport.commands, hasLength(3));
      final options = transport.commands.last['options'] as Map;
      expect(options['windowBackdrop']['gradient']['colors'][1], '#aaccff');
      final selected = _snapshot(
        name: 'renamed.luau',
        dirty: true,
        accent: '#aaccff',
      )..['activeId'] = 'b';
      await service.synchronize(selected);
      expect(transport.commands, hasLength(4));
      expect(transport.commands.last['activeId'], 'b');
      await service.synchronize(selected);
      expect(transport.commands, hasLength(4));
    },
  );

  test(
    'mutating caller-owned maps cannot alter the acknowledged snapshot',
    () async {
      final snapshot = _snapshot(name: 'caller.lua');
      await service.synchronize(snapshot);
      expect(transport.commands, hasLength(2));
      (snapshot['documents'] as List).first['name'] = 'mutated.lua';
      final options = snapshot['options'] as Map;
      options['windowBackdrop']['gradient']['colors'][1] = '#ff5577';
      await service.synchronize(snapshot);
      expect(transport.commands, hasLength(3));
      expect(
        (transport.commands.last['documents'] as List).first['name'],
        'mutated.lua',
      );
      expect(
        transport
            .commands
            .last['options']['windowBackdrop']['gradient']['colors'][1],
        '#ff5577',
      );
      await service.synchronize(snapshot);
      expect(transport.commands, hasLength(3));
    },
  );

  test('a stopped renderer receives a complete snapshot on retry', () async {
    await transport.message({
      'type': 'change',
      'id': 'a',
      'content': 'print("kept on retry")',
    });
    await service.synchronize(_snapshot(content: 'print("kept on retry")'));
    expect(transport.commands, hasLength(1));
    await transport.message({
      'type': 'hostError',
      'message': 'Renderer stopped',
    });
    expect(service.ready, false);
    await service.initialize();
    expect(service.ready, true);
    expect(
      transport.calls.where((call) => call.method == 'create'),
      hasLength(2),
    );
    expect(transport.commands, hasLength(2));
    expect(
      (transport.commands.last['documents'] as List).first['content'],
      'print("kept on retry")',
    );
    expect(transport.commands.last['options'], _snapshot()['options']);
  });

  test(
    'a failed platform send can retry the same requested snapshot',
    () async {
      transport.failSend = true;
      await service.synchronize(_snapshot(content: 'print("retry send")'));
      expect(service.error, isNotNull);
      expect(transport.commands, hasLength(1));
      transport.failSend = false;
      await service.synchronize(_snapshot(content: 'print("retry send")'));
      expect(transport.commands, hasLength(2));
      expect(
        (transport.commands.last['documents'] as List).first['content'],
        'print("retry send")',
      );
    },
  );

  test(
    'a failed in-flight send after native typing can retry without overwriting it',
    () async {
      final gate = transport.sendGate = Completer<void>();
      transport.sendEntered = Completer<void>();
      final pending = service.synchronize(_snapshot(accent: '#44ccaa'));
      await transport.sendEntered!.future;
      await transport.message({
        'type': 'change',
        'id': 'a',
        'content': 'print("kept after failure")',
      });
      transport.sendGate = null;
      gate.completeError(PlatformException(code: 'send_failed'));
      await pending;
      final before = transport.commands.length;
      await service.synchronize(
        _snapshot(content: 'print("kept after failure")', accent: '#44ccaa'),
      );
      expect(transport.commands, hasLength(before + 1));
      final latest = (transport.commands.last['documents'] as List).first;
      expect(latest['content'], 'print("kept after failure")');
      expect(latest['nativeEcho'], true);
      expect(service.error, isNull);
    },
  );

  test(
    'an older failing send cannot invalidate a newer successful snapshot',
    () async {
      final gate = transport.sendGate = Completer<void>();
      transport.sendEntered = Completer<void>();
      final pending = service.synchronize(_snapshot(accent: '#44ccaa'));
      await transport.sendEntered!.future;
      transport.sendGate = null;
      final newer = _snapshot(
        content: 'print("newer request")',
        accent: '#aaccff',
      );
      await service.synchronize(newer);
      final before = transport.commands.length;
      gate.completeError(PlatformException(code: 'old_send_failed'));
      await pending;
      expect(service.error, isNull);
      await service.synchronize(newer);
      expect(transport.commands, hasLength(before));
      final latest = (transport.commands.last['documents'] as List).first;
      expect(latest['content'], 'print("newer request")');
    },
  );

  test(
    'identical errors do not keep notifying a listener that retries sync',
    () async {
      transport.failSend = true;
      var notifications = 0;
      final retries = <Future<void>>[];
      final snapshot = _snapshot(content: 'print("retry from listener")');
      service.addListener(() {
        notifications++;
        // Bound the fixture even if a regression reintroduces notification loops.
        if (service.error != null && notifications < 4) {
          retries.add(service.synchronize(snapshot));
        }
      });
      await service.synchronize(snapshot);
      for (var index = 0; index < retries.length; index++) {
        await retries[index];
      }
      expect(notifications, 1);
      expect(retries, hasLength(1));
      expect(transport.commands, hasLength(1));
      expect(service.error, 'send_failed');

      transport.failSend = false;
      await service.synchronize(snapshot);
      expect(service.error, isNull);
      expect(notifications, 2);
      expect(transport.commands, hasLength(2));
    },
  );

  test(
    'an interrupted theme request cannot send stale text over newer native edits',
    () async {
      transport.themeGate = Completer<void>();
      transport.themeEntered = Completer<void>();
      final pending = service.synchronize(_snapshot(brightness: 'light'));
      await transport.themeEntered!.future;
      await transport.message({
        'type': 'change',
        'id': 'a',
        'content': 'print("newer native edit")',
      });
      await service.synchronize(
        _snapshot(content: 'print("newer native edit")', brightness: 'light'),
      );
      transport.themeGate!.complete();
      await pending;
      expect(transport.commands, hasLength(2));
      final latest = transport.commands.last;
      expect(
        (latest['documents'] as List).first['content'],
        'print("newer native edit")',
      );
      expect((latest['documents'] as List).first['nativeEcho'], true);
      expect(latest['options']['brightness'], 'light');
      await service.synchronize(
        _snapshot(content: 'print("newer native edit")', brightness: 'light'),
      );
      expect(transport.commands, hasLength(2));
    },
  );

  test(
    'a native edit during a platform send remains the acknowledged model',
    () async {
      transport.sendGate = Completer<void>();
      transport.sendEntered = Completer<void>();
      final pending = service.synchronize(_snapshot(accent: '#44ccaa'));
      await transport.sendEntered!.future;
      await transport.message({
        'type': 'change',
        'id': 'a',
        'content': 'print("typed during send")',
      });
      transport.sendGate!.complete();
      await pending;
      final before = transport.commands.length;
      await service.synchronize(
        _snapshot(content: 'print("typed during send")', accent: '#44ccaa'),
      );
      expect(transport.commands, hasLength(before));
      expect(changes.last, ('a', 'print("typed during send")'));
    },
  );
}
