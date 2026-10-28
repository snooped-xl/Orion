import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/auto_update_models.dart';
import 'package:orion/services/auto_update_service.dart';
import 'package:orion/services/flatpak_update_service.dart';
import 'package:orion/state/orion_controller.dart';

void main() {
  late Directory temporary;
  late File info;
  const ref = 'dev.snooped.orion/x86_64/stable';
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('orion-update-test-');
    info = File('${temporary.path}/flatpak-info');
    await info.writeAsString('''[Instance]
app-path=/var/lib/flatpak/app/$ref/old/files
arch=x86_64
branch=stable
instance-id=12345
''');
  });
  tearDown(() => temporary.delete(recursive: true));

  test(
    'all host update and restart commands use a host-visible working directory',
    () async {
      final commands = <List<String>>[];
      final updater = FlatpakUpdateService(
        infoFile: info,
        run: (exe, args) async {
          expect(exe, 'flatpak-spawn');
          expect(args.take(2), ['--host', '--directory=/']);
          final cmd = args.skip(2).toList();
          commands.add(cmd);
          if (cmd.contains('list')) {
            return ProcessResult(0, 0, 'user\nsystem\n', '');
          }
          if (cmd.contains('info')) {
            return ProcessResult(
              0,
              0,
              '${cmd.contains('--user') ? '/home/test/.local/share' : '/var/lib'}/flatpak/app/$ref/newer-deployment\n',
              '',
            );
          }
          return ProcessResult(0, 0, '', '');
        },
      );
      final installation = await updater.install(
        File('${temporary.path}/Orion.flatpak'),
      );
      expect(installation.scope, '--system');
      expect(commands.last, [
        'flatpak',
        'install',
        '--system',
        '--or-update',
        '--bundle',
        '--assumeyes',
        '${temporary.path}/Orion.flatpak',
      ]);
      await updater.scheduleRestart(installation, temporary);
      expect(commands.last.first, '/bin/sh');
      expect(commands.last, isNot(contains('--watch-bus')));
    },
  );

  test(
    'restart waits for its instance and preserves a workspace containing quotes',
    () async {
      final bin = Directory('${temporary.path}/bin')..createSync();
      final calls = File('${temporary.path}/calls');
      final counter = File('${temporary.path}/counter');
      final fake = File('${bin.path}/flatpak');
      await fake.writeAsString('''#!/bin/sh
if [ "\$1" = ps ]; then
  if [ ! -f '${counter.path}' ]; then touch '${counter.path}'; echo 12345; fi
else
  printf '%s\\n' "\$@" > '${calls.path}'
fi
''');
      await Process.run('chmod', ['+x', fake.path]);
      final script = File('${temporary.path}/restart.sh');
      final workspace = "${temporary.path}/user's workspace";
      await script.writeAsString(
        FlatpakUpdateService.buildRestartScript(
          const FlatpakUpdateInstallation(
            scope: '--user',
            ref: ref,
            instanceId: '12345',
          ),
          workspace: workspace,
        ),
      );
      final result = await Process.run(
        '/bin/sh',
        [script.path],
        environment: {'PATH': '${bin.path}:${Platform.environment['PATH']}'},
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(await counter.exists(), isTrue);
      expect(await calls.readAsLines(), [
        'run',
        '--user',
        '--env=ORION_WORKSPACE=$workspace',
        ref,
      ]);
    },
  );

  test('installer failure propagates without scheduling a restart', () async {
    final updater = FlatpakUpdateService(
      infoFile: info,
      run: (exe, args) async {
        if (args.contains('list')) return ProcessResult(0, 0, 'system\n', '');
        if (args.contains('info')) {
          return ProcessResult(0, 0, '/var/lib/flatpak/app/$ref/old', '');
        }
        return ProcessResult(0, 1, '', 'Permission denied');
      },
    );
    await expectLater(
      updater.install(File('Orion.flatpak')),
      throwsA(
        isA<ProcessException>().having(
          (e) => e.message,
          'error',
          contains('Permission denied'),
        ),
      ),
    );
    expect(
      await File('${temporary.path}/restart_flatpak.sh').exists(),
      isFalse,
    );
  });

  test(
    'Linux download, checksum, install, save, restart and exit occur in order',
    () async {
      final events = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final payload = utf8.encode('flatpak-test-payload');
      server.listen((request) async {
        request.response.add(
          request.uri.path.endsWith('.sha256')
              ? utf8.encode('${sha256.convert(payload)}  Orion.flatpak\n')
              : payload,
        );
        await request.response.close();
      });
      final updater = FlatpakUpdateService(
        infoFile: info,
        run: (exe, args) async {
          if (args.contains('list')) return ProcessResult(0, 0, 'system\n', '');
          if (args.contains('info')) {
            return ProcessResult(0, 0, '/var/lib/flatpak/app/$ref/old', '');
          }
          if (args.contains('install')) {
            final bundle = File(args.last);
            expect(await bundle.readAsBytes(), payload);
            expect(
              await File('${bundle.parent.path}/Orion.flatpak.sha256').exists(),
              isTrue,
            );
            addTearDown(() => bundle.parent.delete(recursive: true));
            events.add('install');
          } else {
            events.add('restart');
          }
          return ProcessResult(0, 0, '', '');
        },
      );
      final service = AutoUpdateService(
        platformOverride: 'linux',
        isFlatpakOverride: () => true,
        flatpakUpdater: updater,
        exitAppHandler: (_) => events.add('exit'),
      );
      addTearDown(service.dispose);
      final release = OrionRelease.fromJson({
        'tag_name': 'v99.0.0',
        'assets': [
          for (final name in ['Orion.flatpak', 'Orion.flatpak.sha256'])
            {
              'name': name,
              'size': 0,
              'browser_download_url': 'http://127.0.0.1:${server.port}/$name',
            },
        ],
      });
      await service.downloadAndApply(
        release,
        beforeRestart: () async => events.add('save'),
      );
      expect(events, ['install', 'save', 'restart', 'exit']);
    },
  );

  test(
    'startup ignores a persisted recent check and saves edits before restart',
    () async {
      final updater = _RecordingUpdater();
      final controller = OrionController(
        storageDirectory: temporary,
        autoUpdateService: updater,
      );
      await controller.initialize();
      await controller.checkForUpdates(manual: true);
      controller.newDocument(name: 'keep.lua', content: 'unsaved edit');
      controller.flushEditorForUpdate = () async {
        controller.updateDocumentContent(
          controller.activeDocument.id,
          'latest editor edit',
        );
      };
      await controller.checkForUpdates(startup: true);
      expect(updater.lastTime, isNull);
      await controller.applyPendingUpdate(
        OrionRelease.fromJson({'tag_name': 'v99.0.0'}),
      );
      final state = await File(
        '${temporary.path}/orion-workspace.json',
      ).readAsString();
      expect(state, contains('latest editor edit'));
      controller.dispose();
      await controller.flushPersistence();
    },
  );
}

class _RecordingUpdater extends AutoUpdateService {
  DateTime? lastTime;
  @override
  Future<OrionRelease?> checkForUpdates({
    bool manual = false,
    DateTime? lastCheckTime,
  }) async {
    lastTime = lastCheckTime;
    return null;
  }

  @override
  Future<void> downloadAndApply(
    OrionRelease release, {
    void Function(double, int, int)? onProgress,
    bool restartImmediately = true,
    Future<void> Function()? beforeRestart,
  }) async {
    await beforeRestart?.call();
  }
}
