import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/monaco_editor_service.dart';

class _EditorChannel extends MethodChannel {
  _EditorChannel() : super('orion/test-monaco');
  Future<dynamic> Function(MethodCall)? handler;
  final calls = <MethodCall>[];
  final commands = <Map<String, dynamic>>[];
  bool failCreate = false;
  bool suppressFlush = false;
  Uint8List? preview;
  Completer<Uint8List?>? previewGate;
  bool failPreview = false;
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
    if (method == 'capturePreview') {
      if (failPreview) throw PlatformException(code: 'snapshot_failed');
      return (previewGate == null ? preview : await previewGate!.future) as T?;
    }
    if (method == 'create') {
      if (failCreate) {
        throw PlatformException(
          code: 'unavailable',
          message: 'Test host failed',
        );
      }
      await message({'type': 'ready'});
    } else if (method == 'send') {
      final command = jsonDecode(arguments as String) as Map<String, dynamic>;
      commands.add(command);
      if (command['type'] == 'flush' && !suppressFlush) {
        await message({
          'type': 'flush',
          'requestId': command['requestId'],
          'id': 'a',
          'content': 'latest native edit',
        });
      }
    }
    return null;
  }
}

class _DelayedAssets extends EditorAssetServer {
  final gate = Completer<Uri>();
  bool closed = false;
  @override
  Future<Uri> start() => gate.future;
  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('orion-editor-assets-');
    await File(
      '${directory.path}/index.html',
    ).writeAsString('<p>real fixture</p>');
    await Directory('${directory.path}/vs').create();
    await File(
      '${directory.path}/vs/worker.js',
    ).writeAsString('self.onmessage = () => {};');
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'offline server serves editor and workers on loopback, rejects unrelated paths and methods',
    () async {
      final server = EditorAssetServer(directory: directory);
      final client = HttpClient();
      try {
        final uri = await server.start();
        expect(uri.host, '127.0.0.1');
        expect(await server.start(), uri);
        final page = await (await client.getUrl(uri)).close();
        expect(page.statusCode, 200);
        expect(page.headers.contentType!.mimeType, 'text/html');
        expect(await utf8.decoder.bind(page).join(), '<p>real fixture</p>');
        final worker = await (await client.getUrl(
          uri.resolve('vs/worker.js'),
        )).close();
        expect(worker.statusCode, 200);
        expect(worker.headers.contentType!.mimeType, 'application/javascript');
        await worker.drain<void>();
        for (final path in [
          '/index.html',
          '/editor/missing.js',
          '/editor/%2e%2e/pubspec.yaml',
          '/editor/%2fetc%2fpasswd',
        ]) {
          final response = await (await client.getUrl(
            uri.replace(path: path),
          )).close();
          expect(response.statusCode, 404);
          await response.drain<void>();
        }
        final post = await (await client.postUrl(uri)).close();
        expect(post.statusCode, 404);
        await post.drain<void>();
      } finally {
        client.close(force: true);
        await server.close();
      }
    },
  );

  test(
    'editor synchronization, native changes and flush preserve exact source before save',
    () async {
      final channel = _EditorChannel();
      final changes = <String, String>{};
      final shortcuts = <String>[];
      final service = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (id, source) => changes[id] = source,
        onShortcut: shortcuts.add,
      );
      const snapshot = <String, Object?>{
        'documents': [
          {'id': 'a', 'name': 'a.luau', 'content': 'print("exact")'},
        ],
        'activeId': 'a',
        'options': {'wordWrap': true},
      };
      try {
        await service.synchronize(snapshot);
        expect(channel.commands, isEmpty);
        await service.initialize();
        expect(service.ready, isTrue);
        expect(channel.commands.single['documents'], snapshot['documents']);
        await service.synchronize(snapshot);
        expect(channel.commands, hasLength(1));
        await channel.message({
          'type': 'change',
          'id': 'a',
          'content': 'source with \n tabs\t and "quotes"',
        });
        expect(changes['a'], 'source with \n tabs\t and "quotes"');
        await channel.message({'type': 'shortcut', 'name': 'save'});
        expect(shortcuts, ['save']);
        await channel.message({'type': 'cursor', 'line': 17, 'column': 8});
        expect((service.line, service.column), (17, 8));
        await service.flush();
        expect(changes['a'], 'latest native edit');
        await service.action('paste', text: 'Clipboard exact\ntext');
        expect(channel.commands.last, {
          'type': 'action',
          'name': 'paste',
          'text': 'Clipboard exact\ntext',
        });
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'native surface yields to navigation, transition and modal obscuring independently',
    () async {
      final channel = _EditorChannel();
      final service = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      try {
        await service.initialize();
        await service.setBounds(x: 300, y: 190, width: 820, height: 540);
        Map bounds() =>
            channel.calls.where((c) => c.method == 'setBounds').last.arguments
                as Map;
        expect(bounds(), {
          'x': 300.0,
          'y': 190.0,
          'width': 820.0,
          'height': 540.0,
          'visible': true,
          'reducedMotion': false,
          'uiScale': 1.0,
        });
        service.setObscured(true);
        expect(bounds()['visible'], false);
        service.setActive(false);
        service.setObscured(false);
        expect(bounds()['visible'], false);
        service.setActive(true);
        expect(bounds()['visible'], true);
        service.setTransitioning(true);
        expect(bounds()['visible'], false);
        service.setTransitioning(false);
        expect(bounds()['visible'], true);
        await Future<void>.delayed(Duration.zero);
        final count = channel.calls.length;
        await service.setBounds(x: 300, y: 190, width: 820, height: 540);
        expect(channel.calls, hasLength(count));
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'reduced motion reaches native visibility without resetting unchanged bounds',
    () async {
      final channel = _EditorChannel();
      final service = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      const snapshot = <String, Object?>{
        'documents': [],
        'options': {'reducedMotion': true},
      };
      try {
        await service.synchronize(snapshot);
        await service.initialize();
        await service.setBounds(x: 10, y: 20, width: 600, height: 400);
        Map bounds() =>
            channel.calls.where((c) => c.method == 'setBounds').last.arguments
                as Map;
        expect(bounds()['reducedMotion'], true);
        expect(bounds()['visible'], true);
        final count = channel.calls.length;
        await service.setBounds(x: 10, y: 20, width: 600, height: 400);
        expect(channel.calls, hasLength(count));

        await service.synchronize({
          ...snapshot,
          'options': {'reducedMotion': false},
        });
        expect(bounds()['reducedMotion'], false);
        expect(bounds()['visible'], true);
        service.setObscured(true);
        expect(bounds()['visible'], false);
        await service.synchronize(snapshot);
        expect(bounds()['visible'], false);
        expect(bounds()['reducedMotion'], true);
        service.setObscured(false);
        expect(bounds()['visible'], true);
        expect(bounds()['reducedMotion'], true);
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'UI scale reaches native zoom without multiplying font size or replacing source',
    () async {
      final channel = _EditorChannel();
      final service = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      const source =
          'local part = Instance.new("Part")\npart.Transparency = .25';
      try {
        await service.initialize();
        await service.setBounds(x: 10, y: 20, width: 600, height: 400);
        for (final scale in [.8, 1.0, 1.25]) {
          await service.synchronize({
            'documents': [
              {'id': 'a', 'name': 'a.luau', 'content': source},
            ],
            'activeId': 'a',
            'options': {'fontSize': 22.0, 'uiScale': scale},
          });
          final native =
              channel.calls
                      .lastWhere((call) => call.method == 'setBounds')
                      .arguments
                  as Map;
          expect(native['uiScale'], scale);
          final command = channel.commands.last;
          expect((command['options'] as Map)['fontSize'], 22.0);
          expect((command['documents'] as List).single['content'], source);
        }
        await Future<void>.delayed(Duration.zero);
        final count = channel.calls.length;
        await service.setBounds(x: 10, y: 20, width: 600, height: 400);
        expect(channel.calls, hasLength(count));
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'host failures stay visible as an error and can retry without fake editor content',
    () async {
      final channel = _EditorChannel()..failCreate = true;
      final service = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      try {
        await service.initialize();
        expect(service.ready, false);
        expect(service.error, contains('Test host failed'));
        channel.failCreate = false;
        await service.initialize();
        expect(service.ready, true);
        expect(service.error, isNull);
      } finally {
        service.dispose();
      }
    },
  );
  test(
    'renderer failure hides native surface and retries with cached exact source',
    () async {
      final channel = _EditorChannel();
      final service = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      const body = 'local retained = "exact"\nprint(retained)';
      try {
        await service.synchronize({
          'documents': [
            {'id': 'a', 'name': 'a.luau', 'content': body},
          ],
          'activeId': 'a',
        });
        await service.initialize();
        await service.setBounds(x: 1, y: 87, width: 760, height: 328);
        channel.suppressFlush = true;
        final pending = service.flush();
        await Future<void>.delayed(Duration.zero);
        final failed = expectLater(pending, throwsA(isA<PlatformException>()));
        await channel.message({
          'type': 'hostError',
          'message': 'Renderer stopped',
        });
        await failed;
        expect(service.ready, isFalse);
        expect(service.error, contains('Renderer stopped'));
        expect(channel.calls.last.method, 'setVisible');
        expect(channel.calls.last.arguments, false);
        channel.suppressFlush = false;
        final beforeRecovery = channel.calls.length;
        await service.initialize();
        expect(service.ready, isTrue);
        expect(service.error, isNull);
        expect(
          channel.calls.where((call) => call.method == 'create'),
          hasLength(2),
        );
        final sync = channel.commands.lastWhere(
          (command) => command['type'] == 'sync',
        );
        expect(sync['documents'].single['content'], body);
        expect(
          channel.calls
              .skip(beforeRecovery)
              .where((call) => call.method == 'focus'),
          hasLength(1),
        );
      } finally {
        service.dispose();
      }
    },
  );
  test(
    'disposing while assets initialize never creates a native view afterwards',
    () async {
      final channel = _EditorChannel();
      final assets = _DelayedAssets();
      final service = MonacoEditorService(
        channel: channel,
        server: assets,
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      final startup = service.initialize();
      service.dispose();
      assets.gate.complete(
        Uri.parse('http://127.0.0.1:1234/editor/index.html'),
      );
      await startup;
      expect(assets.closed, true);
      expect(channel.calls.where((call) => call.method == 'create'), isEmpty);
    },
  );

  test(
    'an outgoing editor cannot hide or dispose its replacement native view',
    () async {
      final channel = _EditorChannel();
      final oldEditor = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      final newEditor = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      await oldEditor.initialize();
      await newEditor.initialize();
      await newEditor.setBounds(x: 12, y: 24, width: 600, height: 400);
      final count = channel.calls.length;
      oldEditor.setObscured(true);
      oldEditor.dispose();
      expect(channel.calls, hasLength(count));
      await newEditor.action('find');
      expect(channel.calls.last.method, 'focus');
      expect(channel.commands.last['name'], 'find');
      newEditor.dispose();
      expect(channel.calls.last.method, 'dispose');
    },
  );
  test(
    'native edits are acknowledged without sending stale text replacements back to Monaco',
    () async {
      final channel = _EditorChannel();
      final service = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      try {
        await service.initialize();
        await channel.message({
          'type': 'change',
          'id': 'a',
          'content': 'part.Tr',
        });
        await service.synchronize({
          'documents': [
            {'id': 'a', 'name': 'a.luau', 'content': 'part.Tr'},
          ],
          'activeId': 'a',
        });
        expect(
          (channel.commands.last['documents'] as List).single['nativeEcho'],
          true,
        );
        await service.synchronize({
          'documents': [
            {'id': 'a', 'name': 'a.luau', 'content': 'external replacement'},
          ],
          'activeId': 'a',
        });
        expect(
          (channel.commands.last['documents'] as List).single['nativeEcho'],
          isNull,
        );
      } finally {
        service.dispose();
      }
    },
  );
  test(
    'overlay freeze captures before hiding, caches exact bytes and reveals existing models',
    () async {
      final channel = _EditorChannel()
        ..preview = Uint8List.fromList([137, 80, 78, 71, 1]);
      final service = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      try {
        await service.synchronize({
          'documents': [
            {'id': 'a', 'name': 'sample.lua', 'content': 'print("frame")'},
          ],
          'activeId': 'a',
        });
        await service.initialize();
        await service.setBounds(x: 4, y: 6, width: 640, height: 360);
        channel.calls.clear();
        await service.freezeForOverlay(owner: 'context-menu');
        expect(service.frozenPreview, orderedEquals(channel.preview!));
        expect(service.visible, false);
        final captureIndex = channel.calls.indexWhere(
          (call) => call.method == 'capturePreview',
        );
        final hideIndex = channel.calls.indexWhere(
          (call) =>
              call.method == 'setBounds' &&
              (call.arguments as Map)['visible'] == false,
        );
        expect(captureIndex, greaterThanOrEqualTo(0));
        expect(hideIndex, greaterThan(captureIndex));
        service.setObscured(false, owner: 'context-menu');
        expect(service.visible, true);
        expect(
          (channel.calls
                  .lastWhere((call) => call.method == 'setBounds')
                  .arguments
              as Map)['visible'],
          true,
        );
        expect(
          channel.commands.where((command) => command['type'] == 'sync'),
          hasLength(1),
        );
        expect(service.frozenPreview, orderedEquals(channel.preview!));
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'concurrent overlay owners share one capture and a dismissed pending owner cannot hide later',
    () async {
      final channel = _EditorChannel()..previewGate = Completer<Uint8List?>();
      final service = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      try {
        await service.initialize();
        await service.setBounds(x: 0, y: 0, width: 640, height: 360);
        final first = service.freezeForOverlay(owner: 'first');
        final second = service.freezeForOverlay(owner: 'second');
        expect(service.visible, true);
        expect(
          channel.calls.where((call) => call.method == 'capturePreview'),
          hasLength(1),
        );
        service.setObscured(false, owner: 'first');
        channel.previewGate!.complete(Uint8List.fromList([1, 2, 3]));
        await Future.wait([first, second]);
        expect(service.visible, false);
        service.setObscured(false, owner: 'second');
        expect(service.visible, true);
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'failed new snapshots retain the last successful native frame without blocking the overlay',
    () async {
      final frame = Uint8List.fromList([1, 2, 3, 4]);
      final channel = _EditorChannel()..preview = frame;
      final service = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      try {
        await service.initialize();
        await service.setBounds(x: 0, y: 0, width: 640, height: 360);
        await service.capturePreview();
        channel.failPreview = true;
        await service.freezeForOverlay(owner: 'picker');
        expect(service.visible, false);
        expect(service.frozenPreview, orderedEquals(frame));
        service.setObscured(false, owner: 'picker');
        expect(service.visible, true);
        expect(service.error, isNull);
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'rain textures include current bounds without changing focus or frozen overlays',
    () async {
      final channel = _EditorChannel()
        ..preview = Uint8List.fromList([137, 80, 78, 71, 1]);
      final service = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      try {
        await service.initialize();
        await service.setBounds(x: 80, y: 128, width: 650, height: 290);
        var notifications = 0;
        service.addListener(() => notifications++);
        channel.calls.clear();
        final texture = await service.captureRainTexture();
        expect(texture?['editorPng'], orderedEquals(channel.preview!));
        expect(texture?['editorX'], 80);
        expect(texture?['editorY'], 128);
        expect(texture?['editorWidth'], 650);
        expect(texture?['editorHeight'], 290);
        expect(service.frozenPreview, isNull);
        expect(service.visible, isTrue);
        expect(notifications, 0);
        expect(channel.calls.map((call) => call.method), ['capturePreview']);
        expect(channel.calls.single.arguments, {'maxDimension': 2048});
        channel.previewGate = Completer<Uint8List?>();
        final sameBounds = service.captureRainTexture();
        await service.setBounds(x: 80, y: 128, width: 650, height: 290);
        channel.previewGate!.complete(channel.preview);
        expect(await sameBounds, isNotNull);
        service.setObscured(true, owner: 'menu');
        channel.calls.clear();
        expect(await service.captureRainTexture(), isNull);
        expect(channel.calls, isEmpty);
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'rain rejects a native texture captured before the editor moved or hid',
    () async {
      final channel = _EditorChannel()..previewGate = Completer<Uint8List?>();
      final service = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      try {
        await service.initialize();
        await service.setBounds(x: 80, y: 128, width: 650, height: 290);
        final capture = service.captureRainTexture();
        await service.setBounds(x: 90, y: 128, width: 600, height: 290);
        channel.previewGate!.complete(Uint8List.fromList([1, 2, 3]));
        expect(await capture, isNull);
        expect(service.frozenPreview, isNull);
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'disposing during native capture cannot obscure or cache the next native owner',
    () async {
      final channel = _EditorChannel()..previewGate = Completer<Uint8List?>();
      final service = MonacoEditorService(
        channel: channel,
        server: EditorAssetServer(directory: directory),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      await service.initialize();
      await service.setBounds(x: 0, y: 0, width: 640, height: 360);
      final freeze = service.freezeForOverlay(owner: 'closing-menu');
      service.dispose();
      final count = channel.calls.length;
      channel.previewGate!.complete(Uint8List.fromList([1, 2, 3]));
      await freeze;
      expect(service.frozenPreview, isNull);
      expect(channel.calls, hasLength(count));
    },
  );
}
