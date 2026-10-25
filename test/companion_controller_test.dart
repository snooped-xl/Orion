import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_models.dart';
import 'package:orion/services/companion_controller.dart';
import 'package:orion/state/orion_controller.dart';

class _Request {
  _Request(this.operation, this.payload, this.sequence);
  final String operation;
  final Map<String, Object?> payload;
  final int sequence;
  final result = Completer<Map<String, Object?>>();
}

class _Owner {
  _Owner({this.automatic = false});
  final controller = OrionController(persistChanges: false);
  final bool automatic;
  final requests = <_Request>[];
  int ack = 0, revision = 0;

  Map<String, Object?> envelope() => {
    'state': controller.exportWindowState(),
    'ack': ack,
    'revision': revision,
  };

  Future<Map<String, Object?>> send(
    String operation,
    Map<String, Object?> payload,
    int sequence,
  ) {
    final request = _Request(operation, payload, sequence);
    requests.add(request);
    if (automatic) unawaited(answer(request));
    return request.result.future;
  }

  Future<void> answer(_Request request) async {
    Object? result;
    final p = request.payload;
    if (request.sequence > ack) {
      switch (request.operation) {
        case 'flushPersistence':
          await controller.flushPersistence();
          result = controller.persistenceError;
        case 'setDocumentContent':
          controller.updateDocumentContent(
            p['id'] as String,
            p['content'] as String,
          );
        case 'selectDocument':
          controller.selectDocument(p['id'] as String);
        case 'insertDocument':
          controller.insertSharedDocument(
            EditorDocument.fromJson(
              Map<String, dynamic>.from(p['document'] as Map),
            )!,
          );
        case 'renameDocument':
          controller.renameDocument(p['id'] as String, p['name'] as String);
        case 'closeDocument':
          final replacement = p['replacement'];
          if (replacement is Map && controller.documents.length == 1) {
            controller.insertSharedDocument(
              EditorDocument.fromJson(Map<String, dynamic>.from(replacement))!,
            );
          }
          controller.closeDocument(p['id'] as String);
        case 'reorderDocuments':
          final requested = (p['ids'] as List).cast<String>();
          final existing = controller.documents.map((d) => d.id).toSet();
          controller.reorderDocuments([
            ...requested.where(existing.contains),
            ...existing.where((id) => !requested.contains(id)),
          ]);
        case 'setInterfacePreference':
          controller.setInterfacePreference(
            InterfacePreset.values.byName(p['preset'] as String),
            p['key'] as String,
            p['value'],
          );
        case 'resetInterfacePreferences':
          controller.resetInterfacePreferences(
            InterfacePreset.values.byName(p['preset'] as String),
          );
        case 'updateSynapsePreferences':
          final patch = p['patch'] as Map;
          controller.applyWindowState({
            ...controller.exportWindowState(),
            'synapsePreferences': {
              ...controller.synapsePreferences.toJson(),
              ...patch,
              if (patch['themeColors'] is Map)
                'themeColors': {
                  ...controller.synapsePreferences.themeColors,
                  ...patch['themeColors'] as Map,
                },
            },
          });
        case 'setPreference':
          switch (p['key']) {
            case 'uiScale':
              controller.setUiScale((p['value'] as num).toDouble());
            case 'wordWrap':
              controller.setWordWrap(p['value'] as bool);
            case 'themeMode':
              controller.setThemeMode(
                ThemeMode.values.byName(p['value'] as String),
              );
          }
        case 'saveDocument':
          result = await controller.saveDocumentToPath(
            p['id'] as String,
            p['path'] as String,
          );
        case 'importDocument':
          result = (await controller.importDocumentFromPath(
            p['path'] as String,
            replaceId: p['replaceId'] as String?,
          ))?.toJson();
        case 'attach':
          controller.attach();
        case 'execute':
          controller.execute(
            source: p['source'] as String?,
            name: p['name'] as String?,
          );
        case 'clearActivities':
          controller.clearActivities();
        default:
          throw StateError('Unhandled test operation ${request.operation}');
      }
      ack = request.sequence;
      revision++;
    }
    request.result.complete({'envelope': envelope(), 'result': result});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> tick() => Future<void>.delayed(Duration.zero);

  test('companion windows mirror the active Relapse connection', () {
    if (!Platform.isLinux) return;
    final owner = OrionController(persistChanges: false);
    owner.setRelapseSupportEnabled(true);
    final state = {
      ...owner.exportWindowState(),
      'relapseActive': true,
      'relapseConnected': true,
      'relapseReady': true,
      'relapseOutputCaptureActive': true,
      'relapseSession': 42,
      'relapseSocketPath': '/tmp/relapse.sock',
      'relapseSocketPaths': ['/tmp/relapse.sock', '/tmp/relapse-alt.sock'],
      'relapseConnectedSocketPaths': [
        '/tmp/relapse.sock',
        '/tmp/relapse-alt.sock',
      ],
      'relapseReadySocketPaths': ['/tmp/relapse.sock'],
      'relapseSessions': {
        '/tmp/relapse.sock': 42,
        '/tmp/relapse-alt.sock': 99,
      },
    };
    final child = CompanionController(
      initialState: state,
      sendCommand: (_, _, _) async => {},
    );
    addTearDown(() {
      child.dispose();
      owner.dispose();
    });

    expect(child.usesRelapseSupport, isTrue);
    expect(child.bridgeConnected, isTrue);
    expect(child.relapseReady, isTrue);
    expect(child.relapseOutputCaptureActive, isTrue);
    expect(
      child.bridgeClients.map((c) => c.identifier),
      ['Relapse', 'Relapse · alt'],
    );
    expect(child.relapseTargetCount, 1);
  });

  test(
    'rapid edits survive old acknowledgments without intermediate rollback or feedback',
    () async {
      final owner = _Owner();
      final child = CompanionController(
        initialState: owner.controller.exportWindowState(),
        sendCommand: owner.send,
      );
      addTearDown(() {
        child.dispose();
        owner.controller.dispose();
      });
      final id = child.activeDocumentId;
      final original = owner.envelope();
      child.updateDocumentContent(id, 'p');
      child.updateDocumentContent(id, 'pr');
      child.updateDocumentContent(id, 'print("latest")');
      final observed = <String>[];
      child.addListener(() => observed.add(child.activeDocument.content));
      await tick();
      expect(owner.requests.length, 1);
      child.acceptEnvelope(original);
      expect(child.activeDocument.content, 'print("latest")');
      expect(observed, ['print("latest")']);
      await owner.answer(owner.requests[0]);
      await tick();
      expect(owner.requests.length, 2);
      expect(child.activeDocument.content, 'print("latest")');
      await owner.answer(owner.requests[1]);
      await tick();
      expect(owner.requests.length, 3);
      expect(child.activeDocument.content, 'print("latest")');
      await owner.answer(owner.requests[2]);
      await child.flushCommands();
      expect(owner.requests.map((r) => r.sequence), [1, 2, 3]);
      expect(owner.controller.activeDocument.content, 'print("latest")');
      expect(child.pendingCommandCount, 0);
      expect(observed.every((value) => value == 'print("latest")'), true);
    },
  );

  test(
    'revision ordering and fixed undocked document ignore primary selection changes',
    () async {
      final owner = _Owner(automatic: true);
      final fixed = owner.controller.activeDocumentId;
      final other = owner.controller
          .newDocument(name: 'other.lua', content: 'other')
          .id;
      final child = CompanionController(
        initialState: owner.controller.exportWindowState(),
        sendCommand: owner.send,
        documentId: fixed,
      );
      addTearDown(() {
        child.dispose();
        owner.controller.dispose();
      });
      expect(child.activeDocumentId, fixed);
      final old = owner.envelope();
      owner.controller.updateDocumentContent(fixed, 'new parent text');
      owner.revision = 10;
      child.acceptEnvelope(owner.envelope());
      child.acceptEnvelope(old);
      expect(child.activeDocument.content, 'new parent text');
      expect(child.activeDocumentId, fixed);
      expect(owner.controller.activeDocumentId, other);
      child.updateDocumentContent(fixed, 'child edit');
      await child.flushCommands();
      expect(
        owner.controller.documents.singleWhere((d) => d.id == fixed).content,
        'child edit',
      );
      expect(owner.controller.activeDocumentId, other);
    },
  );

  test(
    'settings changes are optimistic and rebased with unrelated parent preferences',
    () async {
      final owner = _Owner();
      final child = CompanionController(
        initialState: owner.controller.exportWindowState(),
        sendCommand: owner.send,
      );
      addTearDown(() {
        child.dispose();
        owner.controller.dispose();
      });
      child.setInterfacePreference(InterfacePreset.krnl, 'alwaysOnTop', true);
      child.updateSynapsePreferences(
        themeAccent: const Color(0xff123456),
        compactTabs: true,
      );
      child.setUiScale(1.2);
      owner.controller.setInterfacePreference(
        InterfacePreset.krnl,
        'opacityFade',
        true,
      );
      owner.controller.updateSynapsePreferences(
        themeColors: {'shell.custom': 0xffabcdef},
      );
      owner.revision++;
      child.acceptEnvelope(owner.envelope());
      expect(child.getInterfacePreferences(InterfacePreset.krnl), {
        'alwaysOnTop': true,
        'opacityFade': true,
      });
      expect(child.synapsePreferences.themeAccent, const Color(0xff123456));
      expect(child.synapsePreferences.themeColors['shell.custom'], 0xffabcdef);
      expect(child.synapsePreferences.compactTabs, true);
      expect(child.uiScale, 1.2);
      for (var index = 0; index < 3; index++) {
        await tick();
        await owner.answer(owner.requests[index]);
      }
      await child.flushCommands();
      expect(owner.controller.getInterfacePreferences(InterfacePreset.krnl), {
        'alwaysOnTop': true,
        'opacityFade': true,
      });
      expect(
        owner.controller.synapsePreferences.themeAccent,
        const Color(0xff123456),
      );
      expect(owner.controller.uiScale, 1.2);
    },
  );

  test(
    'a late acknowledged revision cannot roll back newer primary preferences',
    () async {
      final owner = _Owner();
      final child = CompanionController(
        initialState: owner.controller.exportWindowState(),
        sendCommand: owner.send,
      );
      addTearDown(() {
        child.dispose();
        owner.controller.dispose();
      });
      final id = child.activeDocumentId;
      child.updateDocumentContent(id, 'first');
      await tick();
      owner.controller.updateDocumentContent(id, 'first');
      final oldReply = {
        'state': owner.controller.exportWindowState(),
        'ack': 1,
        'revision': 2,
      };
      child.updateDocumentContent(id, 'latest');
      owner.controller.setInterfacePreference(
        InterfacePreset.krnl,
        'alwaysOnTop',
        true,
      );
      owner.revision = 3;
      child.acceptEnvelope(owner.envelope());
      expect(child.activeDocument.content, 'latest');
      owner.requests[0].result.complete({'envelope': oldReply, 'result': null});
      await tick();
      expect(
        child.getInterfacePreferences(InterfacePreset.krnl)['alwaysOnTop'],
        true,
      );
      expect(child.activeDocument.content, 'latest');
      owner.ack = 1;
      await owner.answer(owner.requests[1]);
      await child.flushCommands();
      expect(child.activeDocument.content, 'latest');
      expect(child.pendingCommandCount, 0);
    },
  );
  test(
    'created and last-tab replacement IDs remain stable through replay',
    () async {
      final owner = _Owner();
      final child = CompanionController(
        initialState: owner.controller.exportWindowState(),
        sendCommand: owner.send,
      );
      addTearDown(() {
        child.dispose();
        owner.controller.dispose();
      });
      child.closeDocument(child.activeDocumentId);
      final replacement = child.activeDocumentId;
      child.renameDocument(replacement, 'replacement.lua');
      child.acceptEnvelope(owner.envelope());
      expect(child.activeDocumentId, replacement);
      expect(child.activeDocument.name, 'replacement.lua');
      for (var index = 0; index < 2; index++) {
        await tick();
        await owner.answer(owner.requests[index]);
      }
      await child.flushCommands();
      expect(owner.controller.activeDocumentId, replacement);
      expect(owner.controller.activeDocument.name, 'replacement.lua');
      final next = child.newDocument(name: 'next.lua', content: 'next');
      child.updateDocumentContent(next.id, 'newer');
      child.acceptEnvelope(owner.envelope());
      expect(child.activeDocumentId, next.id);
      expect(child.activeDocument.content, 'newer');
      for (var index = 2; index < 4; index++) {
        await tick();
        await owner.answer(owner.requests[index]);
      }
      await child.flushCommands();
      expect(owner.controller.activeDocumentId, next.id);
      expect(owner.controller.activeDocument.content, 'newer');
    },
  );

  test(
    'canonical reordering rebases over a newly created primary tab',
    () async {
      final owner = _Owner();
      final first = owner.controller.activeDocumentId;
      final second = owner.controller.newDocument(name: 'second.lua').id;
      final child = CompanionController(
        initialState: owner.controller.exportWindowState(),
        sendCommand: owner.send,
      );
      addTearDown(() {
        child.dispose();
        owner.controller.dispose();
      });
      child.reorderDocuments([second, first]);
      final third = owner.controller.newDocument(name: 'third.lua').id;
      owner.revision++;
      child.acceptEnvelope(owner.envelope());
      expect(child.documents.map((d) => d.id), [second, first, third]);
      await tick();
      await owner.answer(owner.requests.single);
      await child.flushCommands();
      expect(owner.controller.documents.map((d) => d.id), [
        second,
        first,
        third,
      ]);
    },
  );

  test(
    'save updates actual disk metadata while newer pending typing stays dirty',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'orion-companion-save-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final owner = _Owner();
      final child = CompanionController(
        initialState: owner.controller.exportWindowState(),
        sendCommand: owner.send,
      );
      addTearDown(() {
        child.dispose();
        owner.controller.dispose();
      });
      final id = child.activeDocumentId;
      child.updateDocumentContent(id, 'saved version');
      await tick();
      await owner.answer(owner.requests[0]);
      await child.flushCommands();
      final path = '${directory.path}/source.lua';
      final saving = child.saveDocumentToPath(id, path);
      await tick();
      child.updateDocumentContent(id, 'new unsaved version');
      await owner.answer(owner.requests[1]);
      expect(await saving, true);
      expect(child.activeDocument.filePath, path);
      expect(child.activeDocument.savedContent, 'saved version');
      expect(child.activeDocument.content, 'new unsaved version');
      expect(child.activeDocument.isDirty, true);
      expect(await File(path).readAsString(), 'saved version');
      await tick();
      await owner.answer(owner.requests[2]);
      await child.flushCommands();
      expect(owner.controller.activeDocument.content, 'new unsaved version');
      expect(owner.controller.activeDocument.savedContent, 'saved version');
    },
  );

  test(
    'child initialization and flushing never use local recovery storage',
    () async {
      var pathCalls = 0;
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, (_) async {
            pathCalls++;
            throw StateError('Child recovery storage must not be accessed.');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathChannel, null),
      );
      final owner = _Owner(automatic: true);
      final child = CompanionController(
        initialState: owner.controller.exportWindowState(),
        sendCommand: owner.send,
      );
      addTearDown(() {
        child.dispose();
        owner.controller.dispose();
      });
      await child.initialize();
      child.setWordWrap(true);
      await child.flushPersistence();
      expect(pathCalls, 0);
      expect(owner.controller.wordWrap, true);
      expect(child.initialized, true);
    },
  );

  test(
    'failed transport retains edits and retries the original command sequence',
    () async {
      final owner = _Owner();
      final child = CompanionController(
        initialState: owner.controller.exportWindowState(),
        sendCommand: owner.send,
      );
      addTearDown(() {
        child.dispose();
        owner.controller.dispose();
      });
      child.updateDocumentContent(
        child.activeDocumentId,
        'retained after failure',
      );
      await tick();
      owner.requests[0].result.completeError(
        StateError('Temporarily unavailable'),
      );
      await tick();
      expect(child.commandError, isA<StateError>());
      expect(child.pendingCommandCount, 1);
      expect(child.activeDocument.content, 'retained after failure');
      final retry = child.flushCommands();
      await tick();
      expect(owner.requests.map((r) => r.sequence), [1, 1]);
      await owner.answer(owner.requests[1]);
      await retry;
      expect(owner.controller.activeDocument.content, 'retained after failure');
      expect(child.commandError, isNull);
    },
  );
}
