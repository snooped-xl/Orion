import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/desktop_close_service.dart';
import 'package:orion/state/orion_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'hide is immediate and destruction waits for final editor changes',
    () async {
      final calls = <String>[];
      final editor = Completer<void>();
      final child = Completer<void>();
      final service = DesktopCloseService(
        hide: () async => calls.add('hide'),
        stopWindowChanges: () async => calls.add('stop morph'),
        flushEditor: () async {
          calls.add('flush editor');
          await editor.future;
          calls.add('editor saved');
        },
        closeCompanions: () async {
          calls.add('close children');
          await child.future;
          calls.add('children saved');
        },
        persist: () async => calls.add('persist'),
        closeBridge: () async => calls.add('bridge'),
        destroy: () async => calls.add('destroy'),
        restore: () async => calls.add('restore'),
      );
      final closing = service.close();
      expect(calls, ['hide']);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['hide', 'stop morph', 'flush editor', 'close children']);
      editor.complete();
      await Future<void>.delayed(Duration.zero);
      expect(calls, isNot(contains('persist')));
      child.complete();
      await closing;
      expect(calls.sublist(4), [
        'editor saved',
        'children saved',
        'persist',
        'bridge',
        'destroy',
      ]);
    },
  );

  test('duplicate close requests share a single save and teardown', () async {
    final save = Completer<void>();
    var hides = 0, saves = 0, destroys = 0;
    final service = DesktopCloseService(
      hide: () async {
        hides++;
      },
      persist: () async {
        saves++;
        await save.future;
      },
      destroy: () async {
        destroys++;
      },
      restore: () async {},
    );
    final first = service.close();
    final second = service.close();
    expect(identical(first, second), true);
    save.complete();
    await Future.wait([first, second]);
    await service.close();
    expect((hides, saves, destroys), (1, 1, 1));
  });

  test(
    'failed editor and bridge still save received edits and destroy',
    () async {
      final calls = <String>[];
      final errors = <Object>[];
      final service = DesktopCloseService(
        hide: () async => calls.add('hide'),
        flushEditor: () async => throw StateError('native host stopped'),
        persist: () async => calls.add('persist received edits'),
        closeBridge: () async => throw StateError('socket failed'),
        destroy: () async => calls.add('destroy'),
        restore: () async => calls.add('restore'),
        onCleanupError: (error, stack) => errors.add(error),
      );
      await service.close();
      expect(calls, ['hide', 'persist received edits', 'destroy']);
      expect(errors, hasLength(2));
    },
  );

  test(
    'bridge timeout cannot strand a saved session in a hidden process',
    () async {
      final calls = <String>[];
      final errors = <Object>[];
      final service = DesktopCloseService(
        hide: () async => calls.add('hide'),
        persist: () async => calls.add('persist'),
        closeBridge: () => Completer<void>().future,
        cleanupTimeout: const Duration(milliseconds: 10),
        destroy: () async => calls.add('destroy'),
        restore: () async => calls.add('restore'),
        onCleanupError: (error, stack) => errors.add(error),
      );
      await service.close();
      expect(calls, ['hide', 'persist', 'destroy']);
      expect(errors.single, isA<TimeoutException>());
    },
  );

  for (final stage in ['persist', 'children']) {
    test(
      '$stage failure restores the window and permits a safe retry',
      () async {
        final calls = <String>[];
        var fail = true;
        final service = DesktopCloseService(
          hide: () async => calls.add('hide'),
          closeCompanions: () async {
            calls.add('children');
            if (fail && stage == 'children') throw StateError('unsaved child');
          },
          persist: () async {
            calls.add('persist');
            if (fail && stage == 'persist') throw StateError('disk full');
          },
          destroy: () async => calls.add('destroy'),
          restore: () async => calls.add('restore'),
        );
        await expectLater(service.close(), throwsStateError);
        expect(calls.last, 'restore');
        expect(calls, isNot(contains('destroy')));
        fail = false;
        await service.close();
        expect(calls.last, 'destroy');
        expect(calls.where((call) => call == 'hide'), hasLength(2));
      },
    );
  }

  test(
    'application hides before flush and writes the final edit before destroy',
    () async {
      final directory = await Directory.systemTemp.createTemp('orion-close-');
      final controller = OrionController(storageDirectory: directory);
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('window_manager');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'destroy') {
          final saved =
              jsonDecode(
                    await File(
                      '${directory.path}/orion-workspace.json',
                    ).readAsString(),
                  )
                  as Map;
          expect(
            (saved['documents'] as List).first['content'],
            'last keystroke',
          );
        }
        return null;
      });
      try {
        await DesktopCloseService.closeApp(
          controller: controller,
          nativeWindow: true,
          flushEditor: () async {
            expect(calls, ['hide']);
            controller.updateDocumentContent(
              controller.activeDocumentId,
              'last keystroke',
            );
          },
        );
        expect(calls, ['hide', 'destroy']);
      } finally {
        controller.dispose();
        await controller.flushPersistence();
        messenger.setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'a real workspace write failure restores the application instead of losing edits',
    () async {
      final directory = await Directory.systemTemp.createTemp('orion-close-');
      final blocker = File('${directory.path}/blocked');
      await blocker.writeAsString('not a directory');
      final controller = OrionController(
        storageDirectory: Directory(blocker.path),
      );
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('window_manager');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'isMinimized' ? false : null;
      });
      try {
        await expectLater(
          DesktopCloseService.closeApp(
            controller: controller,
            nativeWindow: true,
          ),
          throwsStateError,
        );
        expect(calls, ['hide', 'isMinimized', 'show', 'focus']);
        expect(controller.persistenceError, isNotNull);
      } finally {
        controller.dispose();
        await controller.flushPersistence();
        messenger.setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      }
    },
  );
}
