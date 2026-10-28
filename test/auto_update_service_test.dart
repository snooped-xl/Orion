import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/auto_update_models.dart';
import 'package:orion/services/auto_update_service.dart';

void main() {
  group('SemVer', () {
    test('parses standard semantic version strings', () {
      final v = SemVer.parse('1.2.3');
      expect(v.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
      expect(v.preRelease, isNull);
      expect(v.build, isNull);
      expect(v.toString(), '1.2.3');
    });

    test('strips leading v and whitespace', () {
      final v = SemVer.parse('  v2.0.1  ');
      expect(v.major, 2);
      expect(v.minor, 0);
      expect(v.patch, 1);
    });

    test('parses pre-release and build metadata', () {
      final v = SemVer.parse('1.0.0-beta.1+build.123');
      expect(v.major, 1);
      expect(v.minor, 0);
      expect(v.patch, 0);
      expect(v.preRelease, 'beta.1');
      expect(v.build, 'build.123');
    });

    test('handles 2-component version gracefully', () {
      final v = SemVer.parse('1.1');
      expect(v.major, 1);
      expect(v.minor, 1);
      expect(v.patch, 0);
    });

    test('compares version precedence correctly', () {
      expect(SemVer.parse('1.1.2') > SemVer.parse('1.1.1'), isTrue);
      expect(SemVer.parse('1.2.0') > SemVer.parse('1.1.9'), isTrue);
      expect(SemVer.parse('2.0.0') > SemVer.parse('1.99.99'), isTrue);
      expect(SemVer.parse('1.1.1') == SemVer.parse('1.1.1'), isTrue);
      expect(SemVer.parse('1.1.0') < SemVer.parse('1.1.1'), isTrue);
      expect(SemVer.parse('1.1.1') >= SemVer.parse('1.1.1'), isTrue);
      expect(SemVer.parse('1.1.1') <= SemVer.parse('1.1.2'), isTrue);
    });

    test('pre-release versions have lower precedence than normal versions', () {
      expect(SemVer.parse('1.0.0-alpha') < SemVer.parse('1.0.0'), isTrue);
      expect(SemVer.parse('1.0.0-beta') > SemVer.parse('1.0.0-alpha'), isTrue);
    });
  });

  group('OrionRelease and Asset resolution', () {
    final sampleJson = {
      'tag_name': 'v1.2.0',
      'name': 'Orion v1.2.0 Release',
      'body': '### Highlights\n- Faster execution\n- Windows auto-update',
      'published_at': '2026-10-28T00:00:00Z',
      'html_url': 'https://github.com/snooped-xl/Orion/releases/tag/v1.2.0',
      'assets': [
        {
          'name': 'Orion.exe',
          'browser_download_url':
              'https://github.com/releases/download/v1.2.0/Orion.exe',
          'size': 15000000,
          'content_type': 'application/vnd.microsoft.portable-executable',
        },
        {
          'name': 'Orion.exe.sha256',
          'browser_download_url':
              'https://github.com/releases/download/v1.2.0/Orion.exe.sha256',
          'size': 64,
          'content_type': 'text/plain',
        },
        {
          'name': 'dev.snooped.orion.flatpak',
          'browser_download_url':
              'https://github.com/releases/download/v1.2.0/dev.snooped.orion.flatpak',
          'size': 35000000,
          'content_type': 'application/octet-stream',
        },
        {
          'name': 'dev.snooped.orion.flatpak.sha256',
          'browser_download_url':
              'https://github.com/releases/download/v1.2.0/dev.snooped.orion.flatpak.sha256',
          'size': 64,
          'content_type': 'text/plain',
        },
        {
          'name': 'Orion-macOS-arm64.zip',
          'browser_download_url':
              'https://github.com/releases/download/v1.2.0/Orion-macOS-arm64.zip',
          'size': 25000000,
          'content_type': 'application/zip',
        },
        {
          'name': 'Orion-macOS-arm64.zip.sha256',
          'browser_download_url':
              'https://github.com/releases/download/v1.2.0/Orion-macOS-arm64.zip.sha256',
          'size': 64,
          'content_type': 'text/plain',
        },
        {
          'name': 'Orion-macOS-x86_64.zip',
          'browser_download_url':
              'https://github.com/releases/download/v1.2.0/Orion-macOS-x86_64.zip',
          'size': 27000000,
          'content_type': 'application/zip',
        },
        {
          'name': 'Orion-macOS-x86_64.zip.sha256',
          'browser_download_url':
              'https://github.com/releases/download/v1.2.0/Orion-macOS-x86_64.zip.sha256',
          'size': 64,
          'content_type': 'text/plain',
        },
      ],
    };

    test('deserializes GitHub release JSON', () {
      final release = OrionRelease.fromJson(sampleJson);
      expect(release.tagName, 'v1.2.0');
      expect(release.versionTag, '1.2.0');
      expect(release.name, 'Orion v1.2.0 Release');
      expect(release.body, contains('Faster execution'));
      expect(release.assets.length, 8);
    });

    test('resolves Windows platform assets', () {
      final release = OrionRelease.fromJson(sampleJson);
      final winAsset = release.windowsAsset;
      expect(winAsset, isNotNull);
      expect(winAsset!.name, 'Orion.exe');

      final shaAsset = release.sha256AssetFor(winAsset);
      expect(shaAsset, isNotNull);
      expect(shaAsset!.name, 'Orion.exe.sha256');
    });

    test('resolves Linux Flatpak platform assets', () {
      final release = OrionRelease.fromJson(sampleJson);
      final linuxAsset = release.linuxFlatpakAsset;
      expect(linuxAsset, isNotNull);
      expect(linuxAsset!.name, 'dev.snooped.orion.flatpak');

      final shaAsset = release.sha256AssetFor(linuxAsset);
      expect(shaAsset, isNotNull);
      expect(shaAsset!.name, 'dev.snooped.orion.flatpak.sha256');
    });

    test('resolves macOS platform assets for both ARM64 and x86_64', () {
      final release = OrionRelease.fromJson(sampleJson);
      final arm64 = release.macOsArm64Asset;
      expect(arm64, isNotNull);
      expect(arm64!.name, 'Orion-macOS-arm64.zip');

      final x64 = release.macOsX64Asset;
      expect(x64, isNotNull);
      expect(x64!.name, 'Orion-macOS-x86_64.zip');
    });
  });

  group('AutoUpdateService check and debouncing', () {
    test('detects available update when remote version is higher', () {
      final service = AutoUpdateService(currentVersion: '1.1.1');

      final release = OrionRelease.fromJson({
        'tag_name': 'v1.2.0',
        'name': 'v1.2.0',
        'body': 'What changed',
        'assets': [],
      });
      expect(release.semver > service.currentSemVer, isTrue);
    });

    test('debounces automatic checks within 4 hours', () async {
      final service = AutoUpdateService(currentVersion: '1.1.1');

      final recent = DateTime.now().subtract(const Duration(hours: 1));
      final result = await service.checkForUpdates(
        manual: false,
        lastCheckTime: recent,
      );

      expect(result, isNull);
      expect(service.status.phase, AutoUpdatePhase.idle);
    });

    test('verifies file SHA-256 correctly', () async {
      final tempDir = await Directory.systemTemp.createTemp('orion_test_sha');
      try {
        final testFile = File('${tempDir.path}/test_bin.exe');
        final bytes = utf8.encode('Orion binary content for hash verification');
        await testFile.writeAsBytes(bytes);

        final expectedHash = sha256.convert(bytes).toString();

        final computed = await AutoUpdateService.computeFileSha256(testFile);
        expect(computed, expectedHash);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('extracts SHA-256 hash string from sha256sum format output', () {
      const hash =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      const outputLine = '$hash  Orion.exe\n';

      expect(AutoUpdateService.extractSha256(hash), hash);
      expect(AutoUpdateService.extractSha256(outputLine), hash);
      expect(AutoUpdateService.extractSha256(hash.toUpperCase()), hash);
    });

    test(
      'Windows replacement targets the portable file and retries launcher locks',
      () {
        final script = AutoUpdateService.buildWindowsUpdateScript(
          pid: 20148,
          newExePath: r"C:\Temp\Orion.exe",
          targetExePath: r"C:\Users\O'Brien & 100% !\Downloads\Orion.exe",
        );
        expect(script, contains('Get-Process -Id 20148'));
        expect(
          script,
          contains(r"C:\Users\O''Brien & 100% !\Downloads\Orion.exe"),
        );
        expect(
          script,
          contains(r'[IO.File]::Replace($staged, $targetExe, $backup)'),
        );
        expect(
          script.indexOf('WaitForExit'),
          lessThan(script.indexOf('[IO.File]::Replace')),
        );
        expect(
          script.indexOf('[IO.File]::Replace'),
          lessThan(script.indexOf('Start-Process')),
        );
        expect(script, contains('AddSeconds(60)'));
        expect(
          AutoUpdateService.resolveWindowsUpdateTarget(
            r'C:\Downloads\Orion.exe\Orion.exe',
          ),
          r'C:\Downloads\Orion.exe',
        );
        expect(
          AutoUpdateService.resolveWindowsUpdateTarget(
            r'C:\Downloads\Renamed.exe',
          ),
          r'C:\Downloads\Renamed.exe',
        );
      },
    );
  });

  group('Windows updater startup acknowledgement', () {
    late Directory directory;
    late File script;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('orion-updater-start-');
      script = File('${directory.path}/apply_update.ps1');
    });
    tearDown(() async => directory.delete(recursive: true));

    test(
      'Windows PowerShell actually executes and acknowledges the script',
      () async {
        await script.writeAsString(
          "\ufeffSet-Content -LiteralPath (\$PSCommandPath + '.ready') -Value ready\n"
          'Start-Sleep -Milliseconds 200\n',
        );
        final process = await AutoUpdateService.startWindowsUpdateHelper(
          script,
        );
        expect(
          await File('${script.path}.ready').readAsString(),
          contains('ready'),
        );
        expect(await process.exitCode, 0);
      },
      skip: !Platform.isWindows
          ? 'Requires native Windows PowerShell 5'
          : false,
    );

    test(
      'uses a hidden attached process and waits for payload staging',
      () async {
        final process = _UpdaterProcess();
        var acknowledged = false;
        final started =
            AutoUpdateService.startWindowsUpdateHelper(
              script,
              processStarter:
                  (
                    executable,
                    arguments, {
                    mode = ProcessStartMode.normal,
                  }) async {
                    expect(executable, 'powershell.exe');
                    expect(mode, ProcessStartMode.normal);
                    expect(arguments.last, script.path);
                    return process;
                  },
            ).then((value) {
              acknowledged = true;
              return value;
            });
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(acknowledged, isFalse);
        await File('${script.path}.ready').writeAsString('ready');
        expect(await started, same(process));
        expect(process.killed, isFalse);
        process.completed.complete(0);
      },
    );

    test('rejects a successful exit that never executes the script', () async {
      final process = _UpdaterProcess()..completed.complete(0);
      await expectLater(
        AutoUpdateService.startWindowsUpdateHelper(
          script,
          processStarter: (_, _, {mode = ProcessStartMode.normal}) async =>
              process,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Orion has stayed open'),
          ),
        ),
      );
    });

    test(
      'terminates a helper that times out before acknowledging startup',
      () async {
        final process = _UpdaterProcess();
        await expectLater(
          AutoUpdateService.startWindowsUpdateHelper(
            script,
            startupTimeout: const Duration(milliseconds: 100),
            processStarter: (_, _, {mode = ProcessStartMode.normal}) async =>
                process,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Startup timed out'),
            ),
          ),
        );
        expect(process.killed, isTrue);
      },
    );
  });
}

class _UpdaterProcess implements Process {
  final completed = Completer<int>();
  var killed = false;
  @override
  Future<int> get exitCode => completed.future;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!completed.isCompleted) completed.complete(-1);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
