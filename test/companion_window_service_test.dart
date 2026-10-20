import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/companion_window.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/synapse_studio_theme.dart';
import 'package:orion/services/companion_window_service.dart';
import 'package:orion/state/orion_controller.dart';

/// Keep the real window-channel codec and the public service API in these tests.
/// Only the native engine/window allocation and IPC transport are simulated.
class _Desktop {
  static const windows = MethodChannel('mixin.one/desktop_multi_window');
  static const transport = MethodChannel(
    'mixin.one/desktop_multi_window/channels',
  );
  static const manager = MethodChannel('window_manager');
  static const native = MethodChannel('orion/window');
  static const codec = StandardMethodCodec();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final parent = WindowController.fromWindowId('main');
  final owner = OrionController(persistChanges: false, useMacSploit: false);
  late final service = CompanionWindowService(owner, parent);
  final allocated = <String>{'main'};
  final creations = <Map<String, Object?>>[];
  final calls = <(String, String)>[];
  final arguments = <String, Map<String, Object?>>{};
  Future<Object?> Function(String id, String method, Object? arguments)?
  childHandler;

  Future<void> initialize() async {
    messenger.setMockMethodCallHandler(windows, (call) async {
      calls.add(('windows', call.method));
      switch (call.method) {
        case 'getWindowDefinition':
          return {'windowId': 'main', 'windowArgument': ''};
        case 'createWindow':
          final configuration = Map<String, Object?>.from(
            call.arguments as Map,
          );
          creations.add(configuration);
          final id = 'child-${creations.length}';
          arguments[id] = Map<String, Object?>.from(
            jsonDecode(configuration['arguments'] as String) as Map,
          );
          allocated.add(id);
          // A native child signals readiness after the create call completes.
          scheduleMicrotask(() => unawaited(request(id, 'ready')));
          return id;
        case 'getAllWindows':
          return [
            for (final id in allocated) {'windowId': id, 'windowArgument': ''},
          ];
        case 'window_destroy':
          allocated.remove((call.arguments as Map)['windowId']);
          return null;
      }
      throw MissingPluginException(call.method);
    });
    messenger.setMockMethodCallHandler(transport, (call) async {
      if (call.method != 'invokeMethod') return null;
      final payload = call.arguments as Map;
      final id = (payload['channel'] as String).split('/').last;
      final method = payload['method'] as String;
      calls.add((id, method));
      if (!allocated.contains(id)) {
        throw PlatformException(code: 'CHANNEL_NOT_FOUND');
      }
      if (childHandler != null) {
        return await childHandler!(id, method, payload['arguments']);
      }
      if (method == 'closeFromOwner') await closeChild(id);
      return null;
    });
    messenger.setMockMethodCallHandler(manager, (call) async {
      calls.add(('manager', call.method));
      return switch (call.method) {
        'getBounds' => {'x': 40.0, 'y': 60.0, 'width': 822.0, 'height': 523.0},
        'isMinimized' => false,
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(('native', call.method));
      return null;
    });
    await service.initialize();
    // The plugin validates the public handler's engine ID in a microtask.
    await Future<void>.delayed(Duration.zero);
  }

  Future<Object?> request(
    String childId,
    String method, [
    Map<String, Object?> payload = const {},
  ]) async {
    final response = Completer<Object?>();
    await messenger.handlePlatformMessage(
      transport.name,
      codec.encodeMethodCall(
        MethodCall('methodCall', {
          'channel': 'mixin.one/window_controller/main',
          'method': method,
          'arguments': {
            'key': arguments[childId]!['key'],
            'windowId': childId,
            ...payload,
          },
        }),
      ),
      (bytes) {
        try {
          response.complete(codec.decodeEnvelope(bytes!));
        } catch (error, stack) {
          response.completeError(error, stack);
        }
      },
    );
    return response.future;
  }

  Future<Object?> command(
    String childId,
    int sequence,
    String operation,
    Map<String, Object?> payload,
  ) => request(childId, 'command', {
    'sequence': sequence,
    'operation': operation,
    'payload': payload,
  });

  Future<void> closeChild(String childId) async {
    await request(childId, 'closed');
    allocated.remove(childId);
  }

  Future<void> dispose() async {
    service.dispose();
    await parent.setWindowMethodHandler(null);
    await Future<void>.delayed(Duration.zero);
    owner.dispose();
    for (final channel in [windows, transport, manager, native]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Desktop desktop;
  setUp(() async {
    desktop = _Desktop();
    await desktop.initialize();
  });
  tearDown(() => desktop.dispose());

  test(
    'each Theme Studio has one independent native engine and applies its whole document atomically',
    () async {
      final content = desktop.owner.activeDocument.content;
      final logoBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
      );
      desktop.owner.setCustomLogo(logoBytes);
      final studios = {
        for (final preset in [
          InterfacePreset.synapseV3,
          InterfacePreset.synapseBlue,
          InterfacePreset.synapseX,
          InterfacePreset.synapse2017,
          InterfacePreset.orion,
        ])
          preset: CompanionThemeStudioKind.forPreset(preset),
      };
      for (final entry in studios.entries) {
        expect(entry.value.themeStudioPreset, entry.key);
        await desktop.service.open(entry.value);
        await desktop.service.open(entry.value);
      }
      expect(desktop.creations, hasLength(5));
      for (final arguments in desktop.arguments.values) {
        expect(
          (arguments['state'] as Map)['customLogo'],
          base64Encode(logoBytes),
        );
      }
      expect(
        desktop.owner.exportWindowState().containsKey('customLogo'),
        false,
      );
      expect(desktop.owner.detachedDocumentIds, isEmpty);
      final document = SynapseStudioTheme(
        name: 'IPC test',
        colors: {'windowBg': 0xff112233},
        windows: {
          'main': SynapseStudioWindow(
            width: 900,
            height: 500,
            elements: {
              'executeButton': SynapseStudioElement(x: 12, fill: 0xff456789),
            },
          ),
        },
      );
      final changes = <Object?>[];
      void changed() => changes.add(
        desktop.owner.getInterfacePreferences(
          InterfacePreset.synapseX,
        )['themeStudio'],
      );
      desktop.owner.addListener(changed);
      await desktop.command('child-3', 1, 'setInterfacePreference', {
        'preset': InterfacePreset.synapseX.name,
        'key': 'themeStudio',
        'value': document.toJson(),
      });
      desktop.owner.removeListener(changed);
      expect(changes, hasLength(1));
      expect(changes.single, document.toJson());
      expect(
        desktop.owner.getInterfacePreferences(
          InterfacePreset.synapseBlue,
        )['themeStudio'],
        isNull,
      );
      expect(desktop.owner.activeDocument.content, content);
      await desktop.service.closeAll();
      expect(desktop.allocated, {'main'});
    },
  );

  test(
    'failed undock startup retains its final draft and redocks its tab',
    () async {
      final id = desktop.owner.activeDocumentId;
      desktop.owner.updateDocumentContent(id, 'print("unsaved original")');
      var closingSawDetached = false;
      desktop.childHandler = (child, method, _) async {
        if (method == 'focus') throw PlatformException(code: 'FOCUS_FAILED');
        if (method == 'closeFromOwner') {
          closingSawDetached = desktop.owner.detachedDocumentIds.contains(id);
          // A ready child can have an unacknowledged edit even when focus fails.
          await desktop.command(child, 1, 'setDocumentContent', {
            'id': id,
            'content': 'print("last native draft")',
          });
          await desktop.closeChild(child);
        }
        return null;
      };

      await expectLater(
        desktop.service.open(
          CompanionWindowKind.synapseV3Editor,
          documentId: id,
        ),
        throwsA(isA<WindowChannelException>()),
      );

      expect(closingSawDetached, true);
      expect(desktop.owner.detachedDocumentIds, isEmpty);
      expect(desktop.owner.activeDocumentId, id);
      final document = desktop.owner.documents.singleWhere((d) => d.id == id);
      expect(document.content, 'print("last native draft")');
      expect(document.isDirty, true);
      expect(desktop.allocated, {'main'});
      expect(desktop.calls, isNot(contains(('manager', 'destroy'))));
    },
  );

  test(
    'failed startup forces child allocation cleanup if its handler is unavailable',
    () async {
      final id = desktop.owner.activeDocumentId;
      desktop.owner.updateDocumentContent(id, 'print("retained")');
      desktop.childHandler = (_, method, _) async {
        if (method == 'focus' || method == 'closeFromOwner') {
          throw PlatformException(code: 'CHANNEL_NOT_FOUND');
        }
        return null;
      };

      await expectLater(
        desktop.service.open(
          CompanionWindowKind.synapseV3Editor,
          documentId: id,
        ),
        throwsA(isA<WindowChannelException>()),
      );

      expect(desktop.owner.detachedDocumentIds, isEmpty);
      expect(desktop.owner.activeDocument.content, 'print("retained")');
      expect(desktop.owner.activeDocument.isDirty, true);
      expect(desktop.allocated, {'main'});
      expect(desktop.calls, contains(('windows', 'window_destroy')));
      expect(desktop.calls, isNot(contains(('manager', 'destroy'))));
    },
  );

  test(
    'simultaneous duplicate IPC sequences commit only one operation',
    () async {
      await desktop.service.open(CompanionWindowKind.synapseXOptions);
      desktop.owner.clearActivities();
      final replies = await Future.wait([
        desktop.command('child-1', 1, 'execute', {'source': 'print("one")'}),
        desktop.command('child-1', 1, 'execute', {'source': 'print("one")'}),
      ]);

      // The default macOS controller routes execution through the native
      // executor asynchronously; this fixture explicitly uses the Bridge path.
      expect(desktop.owner.activities, hasLength(1));
      for (final reply in replies) {
        expect(((reply as Map)['envelope'] as Map)['ack'], 1);
      }
      await expectLater(
        desktop.command('child-1', 3, 'attach', {}),
        throwsA(isA<PlatformException>()),
      );
      expect(desktop.owner.activities, hasLength(1));
      await desktop.command('child-1', 2, 'attach', {});
      expect(desktop.owner.activities, hasLength(2));
    },
  );

  test(
    'closeAll retains a live child after flush failure so it can retry',
    () async {
      final id = desktop.owner.activeDocumentId;
      await desktop.service.open(
        CompanionWindowKind.synapseV3Editor,
        documentId: id,
      );
      var fail = true;
      desktop.childHandler = (child, method, _) async {
        if (method == 'closeFromOwner') {
          if (fail) throw PlatformException(code: 'FLUSH_FAILED');
          await desktop.command(child, 1, 'setDocumentContent', {
            'id': id,
            'content': 'print("retried dirty draft")',
          });
          await desktop.closeChild(child);
        }
        return null;
      };

      await expectLater(
        desktop.service.closeAll(),
        throwsA(isA<WindowChannelException>()),
      );
      expect(desktop.allocated, {'main', 'child-1'});
      expect(desktop.owner.detachedDocumentIds, {id});
      await desktop.service.open(
        CompanionWindowKind.synapseV3Editor,
        documentId: id,
      );
      expect(desktop.creations.length, 1);
      fail = false;
      await desktop.service.closeAll();

      expect(desktop.owner.detachedDocumentIds, isEmpty);
      expect(desktop.allocated, {'main'});
      expect(
        desktop.owner.documents.singleWhere((d) => d.id == id).content,
        'print("retried dirty draft")',
      );
      expect(desktop.calls, isNot(contains(('manager', 'destroy'))));
    },
  );

  test(
    'closeAll tolerates a child disappearing immediately before its close RPC',
    () async {
      final id = desktop.owner.activeDocumentId;
      await desktop.service.open(
        CompanionWindowKind.synapseV3Editor,
        documentId: id,
      );
      // No windows-changed event has reached the owner yet.
      desktop.allocated.remove('child-1');

      await desktop.service.closeAll();

      expect(desktop.owner.detachedDocumentIds, isEmpty);
      expect(desktop.allocated, {'main'});
      expect(desktop.calls, isNot(contains(('manager', 'destroy'))));
    },
  );

  test(
    'shutdown hides all children first and never reopens its owner',
    () async {
      await desktop.service.open(CompanionWindowKind.xenoSettings);
      await desktop.service.open(CompanionWindowKind.synapseXHub);
      desktop.calls.clear();
      desktop.childHandler = (child, method, _) async {
        if (method == 'closeFromOwner') {
          expect(desktop.calls, contains(('child-1', 'hideForShutdown')));
          expect(desktop.calls, contains(('child-2', 'hideForShutdown')));
          await desktop.request(child, 'focusMain');
          await desktop.closeChild(child);
        }
        return null;
      };
      await desktop.service.shutdown();
      expect(desktop.allocated, {'main'});
      expect(desktop.calls, isNot(contains(('manager', 'show'))));
      expect(desktop.calls, isNot(contains(('manager', 'focus'))));
      await desktop.service.open(CompanionWindowKind.synapseXHub);
      expect(desktop.creations, hasLength(2));
    },
  );

  test(
    'cancelled shutdown restores an unsaved child and permits retry',
    () async {
      await desktop.service.open(
        CompanionWindowKind.synapseV3Editor,
        documentId: desktop.owner.activeDocumentId,
      );
      desktop.childHandler = (child, method, _) async {
        if (method == 'closeFromOwner') {
          throw PlatformException(code: 'FLUSH_FAILED');
        }
        return null;
      };
      await expectLater(
        desktop.service.shutdown(),
        throwsA(isA<WindowChannelException>()),
      );
      desktop.calls.clear();
      await desktop.service.cancelShutdown();
      expect(desktop.calls, contains(('child-1', 'focus')));
      expect(desktop.allocated, {'main', 'child-1'});
      expect(desktop.service.acceptsOpens, true);
      desktop.childHandler = null;
      await desktop.service.shutdown();
      expect(desktop.allocated, {'main'});
    },
  );

  test(
    'closing one child retains its sibling and never destroys the owner',
    () async {
      await desktop.service.open(CompanionWindowKind.synapseXOptions);
      await desktop.service.open(CompanionWindowKind.synapseXHub);
      await desktop.closeChild('child-1');

      expect(desktop.allocated, {'main', 'child-2'});
      await desktop.command('child-2', 1, 'setDocumentContent', {
        'id': desktop.owner.activeDocumentId,
        'content': 'print("owner remains alive")',
      });
      await desktop.service.open(CompanionWindowKind.synapseXHub);
      expect(desktop.creations.length, 2);
      expect(
        desktop.owner.activeDocument.content,
        'print("owner remains alive")',
      );
      await desktop.service.closeAll();
      expect(desktop.allocated, {'main'});
      expect(desktop.calls, isNot(contains(('manager', 'destroy'))));
    },
  );

  test('open requested during child flush cannot outlive closeAll', () async {
    await desktop.service.open(CompanionWindowKind.synapseXOptions);
    desktop.childHandler = (child, method, _) async {
      if (method == 'closeFromOwner') {
        // The original child is still registered and flushing at this point.
        await desktop.request(child, 'open', {
          'kind': CompanionWindowKind.synapseXHub.name,
        });
        await desktop.closeChild(child);
      }
      return null;
    };

    await desktop.service.closeAll();
    // Drain work that a mistaken unawaited open enqueued behind closeAll.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(desktop.creations.length, 1);
    expect(desktop.allocated, {'main'});

    // Closing the old interface must not permanently disable future windows.
    desktop.childHandler = null;
    await desktop.service.open(CompanionWindowKind.synapseXHub);
    expect(desktop.creations.length, 2);
    expect(desktop.allocated, {'main', 'child-2'});
    await desktop.service.closeAll();
  });

  test(
    'closeAll invalidates opens already waiting in the lifetime queue',
    () async {
      final flushing = Completer<void>();
      final release = Completer<void>();
      desktop.service.flushEditor = () async {
        if (!flushing.isCompleted) {
          flushing.complete();
          await release.future;
        }
      };
      final first = desktop.service.open(CompanionWindowKind.synapseXOptions);
      await flushing.future;
      final queued = desktop.service.open(CompanionWindowKind.synapseXHub);
      final closing = desktop.service.closeAll();
      release.complete();
      await Future.wait([first, queued, closing]);

      expect(
        desktop.arguments.values.map((args) => args['kind']),
        isNot(contains(CompanionWindowKind.synapseXHub.name)),
      );
      expect(desktop.allocated, {'main'});
      await desktop.service.open(CompanionWindowKind.synapseXHub);
      expect(desktop.allocated, hasLength(2));
      await desktop.service.closeAll();
    },
  );

  test(
    'a removed child cannot send a late open request to the owner',
    () async {
      await desktop.service.open(CompanionWindowKind.synapseXOptions);
      await desktop.closeChild('child-1');

      await expectLater(
        desktop.request('child-1', 'open', {
          'kind': CompanionWindowKind.synapseXHub.name,
        }),
        throwsA(isA<PlatformException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(desktop.creations.length, 1);
      expect(desktop.allocated, {'main'});
    },
  );

  test(
    'interface transition blocks opens until its explicit barrier resets',
    () async {
      await desktop.service.open(CompanionWindowKind.synapseXOptions);
      desktop.service.acceptsOpens = false;
      await desktop.request('child-1', 'open', {
        'kind': CompanionWindowKind.synapseXHub.name,
      });
      await desktop.service.open(CompanionWindowKind.synapseXConsole);
      await desktop.service.closeAll();
      await desktop.service.open(CompanionWindowKind.synapseOgSettings);
      await Future<void>.delayed(Duration.zero);

      expect(desktop.creations.length, 1);
      expect(desktop.allocated, {'main'});
      desktop.service.acceptsOpens = true;
      await desktop.service.open(CompanionWindowKind.synapseOgSettings);
      expect(desktop.creations.length, 2);
      expect(desktop.allocated, {'main', 'child-2'});
      await desktop.service.closeAll();
    },
  );
}
