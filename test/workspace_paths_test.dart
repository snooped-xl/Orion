import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:orion/services/companion_controller.dart';
import 'package:orion/services/workspace_paths.dart';
import 'package:orion/state/orion_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture, root, legacy;
  Future<Directory> prepare({String source = '-- packaged bridge'}) =>
      WorkspacePaths.prepare(
        directory: root,
        legacyDirectory: legacy,
        bridgeSourceLoader: () async => source,
      );
  File workspaceFile(String path) => File('${root.path}/$path');

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('orion-paths-');
    root = Directory('${fixture.path}/home/orion');
    legacy = Directory('${fixture.path}/old-support');
  });
  tearDown(() async => fixture.delete(recursive: true));

  test('Linux workspace uses home regardless of XDG support directory', () {
    expect(
      WorkspacePaths.defaultRootPath(
        platform: 'linux',
        environment: {'HOME': '/home/player', 'XDG_DATA_HOME': '/old-data'},
      ),
      '/home/player/orion',
    );
  });

  test('Windows workspace uses the resolved Documents Known Folder', () {
    expect(
      WorkspacePaths.defaultRootPath(
        platform: 'windows',
        environment: {'USERPROFILE': r'C:\Users\player'},
        documentsDirectory: r'D:\OneDrive\My Documents',
      ),
      r'D:\OneDrive\My Documents/orion',
    );
    expect(
      () => WorkspacePaths.defaultRootPath(
        platform: 'windows',
        environment: {'USERPROFILE': r'C:\Users\player'},
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('explicit automation override wins without home or Known Folder', () {
    for (final platform in ['linux', 'windows']) {
      expect(
        WorkspacePaths.defaultRootPath(
          platform: platform,
          environment: {'ORION_WORKSPACE': '/isolated/fixture'},
        ),
        '/isolated/fixture',
      );
    }
  });

  test(
    'first launch creates the full writable workspace outside bundle',
    () async {
      expect((await prepare()).path, root.absolute.path);
      for (final child in [
        'scripts',
        'scripts/Special',
        'autoexec',
        'themes',
        'cache',
        'backups',
      ]) {
        expect(
          await Directory('${root.path}/$child').exists(),
          isTrue,
          reason: child,
        );
      }
      expect(
        await workspaceFile('scripts/Special/Orion Bridge.lua').readAsString(),
        '-- packaged bridge',
      );
      expect(
        jsonDecode(
          await workspaceFile(WorkspacePaths.markerName).readAsString(),
        )['schema'],
        1,
      );
    },
  );

  test(
    'existing managed bridge is replaced once and backed up, user data remains',
    () async {
      final bridge = workspaceFile('scripts/Special/Orion Bridge.lua');
      await bridge.parent.create(recursive: true);
      await bridge.writeAsString('-- old bridge');
      await workspaceFile(
        'scripts/my-script.lua',
      ).writeAsString('print("keep")');
      await workspaceFile(
        'orion-workspace.json',
      ).writeAsString('{"introCompleted":true}');
      await prepare();
      expect(await bridge.readAsString(), '-- packaged bridge');
      expect(
        await workspaceFile('scripts/my-script.lua').readAsString(),
        'print("keep")',
      );
      expect(
        await workspaceFile('orion-workspace.json').readAsString(),
        '{"introCompleted":true}',
      );
      final backups = await Directory(
        '${root.path}/backups',
      ).list().where((file) => file is File).cast<File>().toList();
      expect(backups, hasLength(1));
      expect(await backups.single.readAsString(), '-- old bridge');
      await bridge.writeAsString('-- local change');
      await prepare();
      expect(await bridge.readAsString(), '-- local change');
      expect(await Directory('${root.path}/backups').list().length, 1);
    },
  );

  test(
    'new bundled bridge revision refreshes resource without resetting workspace',
    () async {
      await prepare(source: '-- v1');
      await workspaceFile('scripts/custom.lua').writeAsString('-- user');
      await prepare(source: '-- v2');
      expect(
        await workspaceFile('scripts/Special/Orion Bridge.lua').readAsString(),
        '-- v2',
      );
      expect(
        await workspaceFile('scripts/custom.lua').readAsString(),
        '-- user',
      );
      expect(await Directory('${root.path}/backups').list().length, 1);
    },
  );

  test(
    'missing managed bridge is repaired even with a current marker',
    () async {
      await prepare();
      await workspaceFile('scripts/Special/Orion Bridge.lua').delete();
      await prepare();
      expect(
        await workspaceFile('scripts/Special/Orion Bridge.lua').readAsString(),
        '-- packaged bridge',
      );
    },
  );

  test(
    'old hidden profile, both script folders and autoexec migrate once',
    () async {
      for (final path in ['scripts/nested', 'Scripts', 'AutoExec']) {
        await Directory('${legacy.path}/$path').create(recursive: true);
      }
      await File('${legacy.path}/scripts/nested/a.lua').writeAsString('-- a');
      await File('${legacy.path}/Scripts/b.lua').writeAsString('-- b');
      await File('${legacy.path}/AutoExec/c.lua').writeAsString('-- c');
      await File('${legacy.path}/orion-workspace.json').writeAsString(
        jsonEncode({
          'introCompleted': true,
          'documents': [
            {
              'filePath': '${legacy.path}/Scripts/b.lua',
              'content': 'unsaved draft',
            },
          ],
          'interfacePreferences': {
            'awp': {'scriptsDirectory': '${legacy.path}/Scripts'},
          },
        }),
      );
      await prepare();
      final state = jsonDecode(
        await workspaceFile('orion-workspace.json').readAsString(),
      );
      expect(state['introCompleted'], isTrue);
      expect(
        state['documents'].single['filePath'],
        '${root.path}/scripts/b.lua',
      );
      expect(state['documents'].single['content'], 'unsaved draft');
      expect(
        state['interfacePreferences']['awp']['scriptsDirectory'],
        '${root.path}/scripts',
      );
      expect(
        await workspaceFile('scripts/nested/a.lua').readAsString(),
        '-- a',
      );
      expect(await workspaceFile('scripts/b.lua').readAsString(), '-- b');
      expect(await workspaceFile('autoexec/c.lua').readAsString(), '-- c');
      await File('${legacy.path}/scripts/late.lua').writeAsString('-- late');
      await prepare();
      expect(await workspaceFile('scripts/late.lua').exists(), isFalse);
      expect(
        await File('${legacy.path}/orion-workspace.json').exists(),
        isTrue,
      );
    },
  );

  test('migration keeps existing destination files and profile', () async {
    await Directory('${legacy.path}/scripts').create(recursive: true);
    await File('${legacy.path}/scripts/same.lua').writeAsString('-- old');
    await File(
      '${legacy.path}/orion-workspace.json',
    ).writeAsString('{"old":true}');
    await Directory('${root.path}/scripts').create(recursive: true);
    await workspaceFile('scripts/same.lua').writeAsString('-- current');
    await workspaceFile(
      'orion-workspace.json',
    ).writeAsString('{"current":true}');
    await prepare();
    expect(
      await workspaceFile('scripts/same.lua').readAsString(),
      '-- current',
    );
    expect(
      await workspaceFile('orion-workspace.json').readAsString(),
      '{"current":true}',
    );
  });

  test(
    'corrupted marker is repaired without discarding saved profile',
    () async {
      await root.create(recursive: true);
      await workspaceFile(WorkspacePaths.markerName).writeAsString('{partial');
      await workspaceFile(
        'orion-workspace.json',
      ).writeAsString('{"saved":true}');
      await prepare();
      expect(
        jsonDecode(
          await workspaceFile(WorkspacePaths.markerName).readAsString(),
        )['schema'],
        1,
      );
      expect(
        await workspaceFile('orion-workspace.json').readAsString(),
        '{"saved":true}',
      );
    },
  );

  test(
    'managed script folder links cannot redirect bridge replacement',
    () async {
      if (Platform.isWindows) {
        return; // Creating links requires optional privileges.
      }
      await root.create(recursive: true);
      final outside = Directory('${fixture.path}/outside');
      await outside.create();
      await Link('${root.path}/scripts').create(outside.path);
      await expectLater(prepare(), throwsA(isA<FileSystemException>()));
      expect(await Directory('${outside.path}/Special').exists(), isFalse);
    },
  );

  test(
    'companion windows inherit resolved primary workspace without provisioning',
    () async {
      final controller = OrionController(storageDirectory: root);
      await controller.initialize();
      final child = CompanionController(
        initialState: controller.exportWindowState(),
        sendCommand: (_, _, _) async => {},
      );
      expect(child.workspaceDirectory.path, root.path);
      expect(child.scriptsDirectory.path, '${root.path}/scripts');
      expect(child.autoexecuteDirectory.path, '${root.path}/autoexec');
      await child.initialize();
      expect(await workspaceFile(WorkspacePaths.markerName).exists(), isFalse);
      child.dispose();
      controller.dispose();
      await controller.flushPersistence();
    },
  );

  test(
    'primary and companion Save As dialogs start in the shared scripts folder',
    () async {
      final controller = OrionController(storageDirectory: root);
      await controller.initialize();
      final child = CompanionController(
        initialState: controller.exportWindowState(),
        sendCommand: (_, _, _) async => {},
      );
      final initialDirectories = <Object?>[];
      const picker = MethodChannel('plugins.flutter.io/file_selector');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(picker, (call) async {
        if (call.method == 'getSavePath') {
          initialDirectories.add((call.arguments as Map)['initialDirectory']);
        }
        return null;
      });
      try {
        expect(await controller.saveAs(), isFalse);
        expect(await child.saveAs(), isFalse);
        expect(initialDirectories, [
          '${root.path}/scripts',
          '${root.path}/scripts',
        ]);
      } finally {
        messenger.setMockMethodCallHandler(picker, null);
        child.dispose();
        controller.dispose();
        await controller.flushPersistence();
      }
    },
  );
}
