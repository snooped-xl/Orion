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
          'browser_download_url': 'https://github.com/releases/download/v1.2.0/Orion.exe',
          'size': 15000000,
          'content_type': 'application/vnd.microsoft.portable-executable',
        },
        {
          'name': 'Orion.exe.sha256',
          'browser_download_url': 'https://github.com/releases/download/v1.2.0/Orion.exe.sha256',
          'size': 64,
          'content_type': 'text/plain',
        },
        {
          'name': 'dev.snooped.orion.flatpak',
          'browser_download_url': 'https://github.com/releases/download/v1.2.0/dev.snooped.orion.flatpak',
          'size': 35000000,
          'content_type': 'application/octet-stream',
        },
        {
          'name': 'dev.snooped.orion.flatpak.sha256',
          'browser_download_url': 'https://github.com/releases/download/v1.2.0/dev.snooped.orion.flatpak.sha256',
          'size': 64,
          'content_type': 'text/plain',
        },
        {
          'name': 'Orion-macOS-arm64.zip',
          'browser_download_url': 'https://github.com/releases/download/v1.2.0/Orion-macOS-arm64.zip',
          'size': 25000000,
          'content_type': 'application/zip',
        },
        {
          'name': 'Orion-macOS-arm64.zip.sha256',
          'browser_download_url': 'https://github.com/releases/download/v1.2.0/Orion-macOS-arm64.zip.sha256',
          'size': 64,
          'content_type': 'text/plain',
        },
        {
          'name': 'Orion-macOS-x86_64.zip',
          'browser_download_url': 'https://github.com/releases/download/v1.2.0/Orion-macOS-x86_64.zip',
          'size': 27000000,
          'content_type': 'application/zip',
        },
        {
          'name': 'Orion-macOS-x86_64.zip.sha256',
          'browser_download_url': 'https://github.com/releases/download/v1.2.0/Orion-macOS-x86_64.zip.sha256',
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
      final service = AutoUpdateService(
        currentVersion: '1.1.1',
      );

      final release = OrionRelease.fromJson({
        'tag_name': 'v1.2.0',
        'name': 'v1.2.0',
        'body': 'What changed',
        'assets': [],
      });
      expect(release.semver > service.currentSemVer, isTrue);
    });

    test('debounces automatic checks within 4 hours', () async {
      final service = AutoUpdateService(
        currentVersion: '1.1.1',
      );

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
      const hash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      const outputLine = '$hash  Orion.exe\n';

      expect(AutoUpdateService.extractSha256(hash), hash);
      expect(AutoUpdateService.extractSha256(outputLine), hash);
      expect(AutoUpdateService.extractSha256(hash.toUpperCase()), hash);
    });

    test("builds robust Windows update batch script", () {
      final script = AutoUpdateService.buildWindowsUpdateScript(
        pid: 20148,
        newExePath: r"C:\Users\User\AppData\Local\Temp\orion_update_v1.13.1\Orion.exe",
        targetExePath: r"C:\Users\User\Downloads\Orion.exe",
      );

      expect(script, contains("set \"ORION_PID=20148\""));
      expect(script, contains(r"set \"NEW_EXE=C:\Users\User\AppData\Local\Temp\orion_update_v1.13.1\Orion.exe\""));
      expect(script, contains(r"set \"TARGET_EXE=C:\Users\User\Downloads\Orion.exe\""));
      expect(script, contains("powershell -NoProfile -NonInteractive -Command"));
      expect(script, contains(r"move /y \"%NEW_EXE%\" \"%TARGET_EXE%\""));
      expect(script, contains(r"start \"\" \"%TARGET_EXE%\""));
      expect(script, contains(r"(goto) 2>nul & del \"%~f0\""));
    });
  });
}
