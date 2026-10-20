import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_models.dart';
import 'package:orion/models/remote_script.dart';
import 'package:orion/services/script_hub_service.dart';
import 'package:orion/state/orion_controller.dart';

RemoteScript item(
  ScriptProvider p,
  String id, {
  String? body = 'print("fixture")',
}) => RemoteScript(
  id: id,
  provider: p,
  title: '$id title',
  game: 'Fixture game',
  description: 'Fixture description',
  body: body,
  rawUrl: 'https://${p.domain}/raw/$id',
  externalUrl: 'https://${p.domain}/script/$id',
);

class FakeHub extends ScriptHubService {
  FakeHub(this.onFetch, {this.onLoad})
    : super(
        transport: (uri, headers) async =>
            const ScriptHttpResponse(statusCode: 200, body: []),
      );
  final Future<ScriptPage> Function(ScriptProvider, String, int) onFetch;
  final Future<String> Function(RemoteScript)? onLoad;
  int sourceLoads = 0;
  bool didClose = false;
  @override
  Future<ScriptPage> fetch(ScriptProvider p, String q, int page) =>
      onFetch(p, q, page);
  @override
  Future<String> loadScript(RemoteScript script) async {
    sourceLoads++;
    if (onLoad != null) return onLoad!(script);
    return script.body ?? 'print("downloaded")';
  }

  @override
  void close() {
    didClose = true;
    super.close();
  }
}

class RecordingExecutionController extends OrionController {
  RecordingExecutionController({
    required super.storageDirectory,
    required super.scriptHubService,
    super.useMacSploit = false,
  });

  final executionRequests = <({String? source, String? name})>[];

  @override
  void execute({String? source, String? name}) {
    executionRequests.add((source: source, name: name));
    super.execute(source: source, name: name);
  }
}

void main() {
  late Directory directory;
  final controllers = <OrionController>[];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('orion-remote-state-');
  });
  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
      await c.flushPersistence();
    }
    controllers.clear();
    await directory.delete(recursive: true);
  });
  Future<OrionController> mount(FakeHub hub) async {
    final c = OrionController(
      storageDirectory: directory,
      scriptHubService: hub,
      useMacSploit: false,
    );
    controllers.add(c);
    await c.initialize();
    return c;
  }

  Future<RecordingExecutionController> mountExecution(FakeHub hub) async {
    final c = RecordingExecutionController(
      storageDirectory: directory,
      scriptHubService: hub,
      useMacSploit: false,
    );
    controllers.add(c);
    await c.initialize();
    return c;
  }

  test(
    'all sources run concurrently and a failed source preserves healthy results',
    () async {
      final pending = <ScriptProvider, Completer<ScriptPage>>{};
      final hub = FakeHub((p, q, page) {
        final task = Completer<ScriptPage>();
        pending[p] = task;
        return task.future;
      });
      final c = await mount(hub);
      final search = c.searchRemoteScripts('studio');
      expect(pending.keys.toSet(), ScriptProvider.values.toSet());
      expect(c.remoteLoading, isTrue);
      pending[ScriptProvider.haxHell]!.completeError(
        const ScriptHubException('HTTP503', statusCode: 503),
      );
      for (final p in ScriptProvider.values.where(
        (p) => p != ScriptProvider.haxHell,
      )) {
        pending[p]!.complete(
          ScriptPage(items: [item(p, 'same')], hasMore: true),
        );
      }
      await search;
      expect(c.remoteLoading, isFalse);
      expect(c.remoteScripts, hasLength(3));
      expect(c.remoteScripts.map((s) => s.key).toSet(), hasLength(3));
      expect(c.providerErrors, {ScriptProvider.haxHell: 'HTTP503'});
      expect(c.remoteHasMore, isTrue);
    },
  );

  test(
    'old search completions never replace results or errors from a newer query',
    () async {
      final pending = <String, Map<ScriptProvider, Completer<ScriptPage>>>{};
      final hub = FakeHub((p, q, page) {
        final task = Completer<ScriptPage>();
        pending.putIfAbsent(q, () => {})[p] = task;
        return task.future;
      });
      final c = await mount(hub);
      final old = c.searchRemoteScripts('old');
      final fresh = c.searchRemoteScripts('new');
      for (final p in ScriptProvider.values) {
        pending['new']![p]!.complete(
          ScriptPage(items: [item(p, 'new')], hasMore: false),
        );
      }
      await fresh;
      expect(c.remoteLoading, isFalse);
      for (final p in ScriptProvider.values) {
        if (p == ScriptProvider.haxHell) {
          pending['old']![p]!.completeError(
            const ScriptHubException('stale failure'),
          );
        } else {
          pending['old']![p]!.complete(
            ScriptPage(items: [item(p, 'old')], hasMore: true),
          );
        }
      }
      await old;
      expect(c.remoteScripts.every((s) => s.id == 'new'), isTrue);
      expect(c.remoteScripts, hasLength(4));
      expect(c.providerErrors, isEmpty);
      expect(c.remoteHasMore, isFalse);
    },
  );

  test(
    'pagination de-duplicates by provider and retries a failed page without skipping it',
    () async {
      final calls = <ScriptProvider, List<int>>{};
      var failBlox = true;
      final c = await mount(
        FakeHub((p, q, page) async {
          calls.putIfAbsent(p, () => []).add(page);
          if (p == ScriptProvider.scriptBlox && page == 2 && failBlox) {
            throw const ScriptHubException('Temporary failure');
          }
          return ScriptPage(
            items: [item(p, 'one'), if (page == 2) item(p, 'two')],
            hasMore: page == 1,
          );
        }),
      );
      await c.searchRemoteScripts('search');
      expect(c.remoteScripts, hasLength(4));
      await c.loadMoreRemoteScripts();
      expect(c.remoteScripts, hasLength(7));
      expect(c.providerErrors.keys, [ScriptProvider.scriptBlox]);
      failBlox = false;
      await c.retryRemoteSource(ScriptProvider.scriptBlox);
      expect(c.remoteScripts, hasLength(8));
      expect(c.providerErrors, isEmpty);
      expect(c.remoteHasMore, isFalse);
      expect(calls[ScriptProvider.scriptBlox], [1, 2, 2]);
    },
  );

  test(
    'saved favorites keep metadata and provider identities and restore selected interface',
    () async {
      final c = await mount(
        FakeHub(
          (p, q, page) async => const ScriptPage(items: [], hasMore: false),
        ),
      );
      c.toggleRemoteFavorite(item(ScriptProvider.scriptBlox, 'same'));
      c.toggleRemoteFavorite(item(ScriptProvider.rscripts, 'same'));
      c.setInterface(InterfacePreset.krnl);
      await c.flushPersistence();
      final json = jsonDecode(
        await File('${directory.path}/orion-workspace.json').readAsString(),
      );
      expect(
        (json['remoteFavorites'] as List).every(
          (entry) => entry['body'] == null,
        ),
        isTrue,
      );
      final restored = await mount(
        FakeHub(
          (p, q, page) async => const ScriptPage(items: [], hasMore: false),
        ),
      );
      expect(restored.remoteFavorites, hasLength(2));
      expect(restored.selectedInterface, InterfacePreset.krnl);
      expect(restored.isRemoteFavorite('scriptBlox:same'), isTrue);
      expect(restored.isRemoteFavorite('rscripts:same'), isTrue);
    },
  );

  test(
    'view and open share a source load and open exact text in a new unsaved file',
    () async {
      final hub = FakeHub(
        (p, q, page) async => const ScriptPage(items: [], hasMore: false),
      );
      final c = await mount(hub);
      final remote = item(
        ScriptProvider.haxHell,
        'example',
        body: '-- exact source\nprint("loaded")',
      );
      final source = await c.loadRemoteScript(remote);
      final opened = await c.openRemoteScript(remote);
      expect(hub.sourceLoads, 1);
      expect(source, remote.body);
      expect(opened?.content, remote.body);
      expect(opened?.filePath, isNull);
      expect(c.activeDocument.id, opened?.id);
    },
  );

  test(
    'direct remote execution uses fetched source and cache without editing or importing tabs',
    () async {
      const source = '-- preserve exact downloaded source\r\nprint("remote")\n';
      final pending = Completer<String>();
      final hub = FakeHub(
        (p, q, page) async => const ScriptPage(items: [], hasMore: false),
        onLoad: (script) => pending.future,
      );
      final c = await mountExecution(hub);
      c.newDocument(
        name: 'local-draft.luau',
        content: 'print("keep my edits")',
      );
      final activeId = c.activeDocument.id;
      final documents = c.documents.map((doc) => doc.toJson()).toList();
      final remote = item(ScriptProvider.rscripts, 'remote-run', body: null);

      final execution = c.executeRemoteScript(remote);
      final viewed = c.loadRemoteScript(remote);
      expect(hub.sourceLoads, 1);
      expect(c.executionRequests, isEmpty);
      expect(
        c.activities.where((a) => a.kind == ActivityKind.execution),
        isEmpty,
      );
      pending.complete(source);
      await execution;
      expect(await viewed, source);

      expect(c.executionRequests, [(source: source, name: remote.title)]);
      final log = c.activities.first;
      expect(log.kind, ActivityKind.execution);
      expect(log.severity, ActivitySeverity.warning);
      expect(log.title, 'No clients connected');
      expect(log.detail, contains(remote.title));
      expect(log.detail, isNot(contains('local-draft.luau')));
      expect(c.activeDocument.id, activeId);
      expect(c.documents.map((doc) => doc.toJson()).toList(), documents);

      await c.executeRemoteScript(remote);
      expect(hub.sourceLoads, 1);
      expect(c.executionRequests, [
        (source: source, name: remote.title),
        (source: source, name: remote.title),
      ]);
      expect(c.activeDocument.id, activeId);
      expect(c.documents.map((doc) => doc.toJson()).toList(), documents);
    },
  );

  test(
    'a failed remote download never executes and retry fetches fresh source',
    () async {
      const source = 'print("retry loaded the actual remote source")';
      var attempts = 0;
      final hub = FakeHub(
        (p, q, page) async => const ScriptPage(items: [], hasMore: false),
        onLoad: (script) async {
          attempts++;
          if (attempts == 1) {
            throw const ScriptHubException('HTTP503', statusCode: 503);
          }
          return source;
        },
      );
      final c = await mountExecution(hub);
      c.newDocument(name: 'unsaved.luau', content: '-- keep this draft');
      final activeId = c.activeDocument.id;
      final documents = c.documents.map((doc) => doc.toJson()).toList();
      final activities = c.activities.map((a) => a.toJson()).toList();
      final remote = item(ScriptProvider.scriptBlox, 'retry-run', body: null);

      await expectLater(
        c.executeRemoteScript(remote),
        throwsA(isA<ScriptHubException>()),
      );
      expect(hub.sourceLoads, 1);
      expect(c.executionRequests, isEmpty);
      expect(c.activities.map((a) => a.toJson()).toList(), activities);
      expect(c.activeDocument.id, activeId);
      expect(c.documents.map((doc) => doc.toJson()).toList(), documents);

      await c.executeRemoteScript(remote);
      expect(hub.sourceLoads, 2);
      expect(c.executionRequests, [(source: source, name: remote.title)]);
      expect(c.activities.first.kind, ActivityKind.execution);
      expect(c.activities.first.detail, contains(remote.title));
      expect(c.activeDocument.id, activeId);
      expect(c.documents.map((doc) => doc.toJson()).toList(), documents);
    },
  );

  test('disposing while remote source loads prevents execution', () async {
    final pending = Completer<String>();
    final hub = FakeHub(
      (p, q, page) async => const ScriptPage(items: [], hasMore: false),
      onLoad: (script) => pending.future,
    );
    final c = await mountExecution(hub);
    final documents = c.documents.map((doc) => doc.toJson()).toList();
    final activeId = c.activeDocument.id;
    final activities = c.activities.map((a) => a.toJson()).toList();
    final remote = item(ScriptProvider.haxHell, 'late-run', body: null);

    final execution = c.executeRemoteScript(remote);
    expect(hub.sourceLoads, 1);
    controllers.remove(c);
    c.dispose();
    expect(hub.didClose, isTrue);
    pending.complete('print("too late")');
    await execution;
    await c.flushPersistence();

    expect(c.executionRequests, isEmpty);
    expect(c.activities.map((a) => a.toJson()).toList(), activities);
    expect(c.activeDocument.id, activeId);
    expect(c.documents.map((doc) => doc.toJson()).toList(), documents);
  });
}
