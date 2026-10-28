import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/auto_update_models.dart';
import 'desktop_launcher.dart';

typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode,
});

/// Service responsible for polling GitHub releases, verifying SHA-256 integrity,
/// downloading platform binaries, and applying updates atomically.
class AutoUpdateService extends ChangeNotifier {
  AutoUpdateService({
    HttpClient? client,
    String? currentVersion,
    String? repoOwner,
    String? repoName,
    this.platformOverride,
    this.archOverride,
    this.targetExeOverride,
    this.isFlatpakOverride,
    ProcessStarter? processStarter,
    this.exitAppHandler,
  })  : _client = client,
        currentVersion = currentVersion ?? defaultCurrentVersion,
        repoOwner = repoOwner ?? 'snooped-xl',
        repoName = repoName ?? 'Orion',
        _processStarter = processStarter ?? Process.start;

  /// Pinned application version reported by the desktop runtime.
  static const String defaultCurrentVersion = '1.1.1';

  final HttpClient? _client;
  final String currentVersion;
  final String repoOwner;
  final String repoName;
  final String? platformOverride;
  final String? archOverride;
  final String? targetExeOverride;
  final bool Function()? isFlatpakOverride;
  final ProcessStarter _processStarter;
  final void Function(int code)? exitAppHandler;

  AutoUpdateStatus _status = const AutoUpdateStatus.idle();
  AutoUpdateStatus get status => _status;

  SemVer get currentSemVer => SemVer.parse(currentVersion);

  String get releasesApiUrl =>
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  /// Check GitHub for newer releases. When [manual] is false, throttled by
  /// [lastCheckTime] with a 4-hour debounce.
  Future<OrionRelease?> checkForUpdates({
    bool manual = false,
    DateTime? lastCheckTime,
  }) async {
    final now = DateTime.now();
    if (!manual && lastCheckTime != null) {
      final difference = now.difference(lastCheckTime);
      if (difference < const Duration(hours: 4)) {
        return null;
      }
    }

    _status = AutoUpdateStatus.checking(lastChecked: lastCheckTime);
    notifyListeners();

    final client = _client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));
    try {
      final request = await client.getUrl(Uri.parse(releasesApiUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'Orion-Desktop/$currentVersion');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github.v3+json');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'GitHub API returned ${response.statusCode}',
          uri: Uri.parse(releasesApiUrl),
        );
      }

      final bodyString = await utf8.decodeStream(response).timeout(const Duration(seconds: 15));
      final json = jsonDecode(bodyString) as Map<String, dynamic>;
      final release = OrionRelease.fromJson(json);

      if (release.semver > currentSemVer) {
        _status = AutoUpdateStatus.updateAvailable(release, checkedAt: now);
        notifyListeners();
        return release;
      } else {
        _status = AutoUpdateStatus.upToDate(checkedAt: now);
        notifyListeners();
        return null;
      }
    } catch (e) {
      _status = AutoUpdateStatus.error(e.toString(), lastChecked: lastCheckTime);
      notifyListeners();
      return null;
    } finally {
      if (_client == null) {
        client.close(force: true);
      }
    }
  }

  /// Download and apply the update for the current platform.
  Future<void> downloadAndApply(
    OrionRelease release, {
    void Function(double progress, int received, int total)? onProgress,
    bool restartImmediately = true,
  }) async {
    final platform = platformOverride ?? defaultTargetPlatform.name.toLowerCase();
    final asset = release.platformAsset(platform: platform, arch: archOverride);
    final checksumAsset = release.platformSha256Asset(platform: platform, arch: archOverride);

    if (asset == null) {
      final message = 'No release asset available for platform: $platform';
      _status = AutoUpdateStatus.error(message);
      notifyListeners();
      throw StateError(message);
    }

    // Determine working download directory
    final tempDir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}orion_update_${release.tagName}');
    if (!tempDir.existsSync()) {
      tempDir.createSync(recursive: true);
    }

    final targetDownloadFile = File('${tempDir.path}${Platform.pathSeparator}${asset.name}');

    try {
      // 1. Download payload file
      await _downloadUrlToFile(
        asset.downloadUrl,
        targetDownloadFile,
        asset.size,
        (progress, received, total) {
          _status = AutoUpdateStatus.downloading(
            release: release,
            progress: progress,
            receivedBytes: received,
            totalBytes: total,
          );
          notifyListeners();
          onProgress?.call(progress, received, total);
        },
      );

      // 2. Download and verify SHA-256 checksum if available
      if (checksumAsset != null) {
        _status = AutoUpdateStatus.verifying(release: release);
        notifyListeners();

        final checksumFile = File('${tempDir.path}${Platform.pathSeparator}${checksumAsset.name}');
        await _downloadUrlToFile(checksumAsset.downloadUrl, checksumFile, checksumAsset.size);

        final checksumContent = await checksumFile.readAsString();
        final expectedHash = extractSha256(checksumContent);

        final actualHash = await computeFileSha256(targetDownloadFile);
        if (actualHash.toLowerCase() != expectedHash) {
          throw FormatException(
            'SHA-256 checksum verification failed. Expected $expectedHash but got $actualHash',
          );
        }
      }

      _status = AutoUpdateStatus.readyToRestart(release: release);
      notifyListeners();

      // 3. Platform specific installer execution
      if (platform.contains('windows')) {
        await _applyWindowsUpdate(targetDownloadFile, restartImmediately: restartImmediately);
      } else if (platform.contains('linux')) {
        await _applyLinuxUpdate(targetDownloadFile, restartImmediately: restartImmediately);
      } else if (platform.contains('macos') || platform.contains('mac')) {
        await _applyMacOsUpdate(targetDownloadFile, tempDir, restartImmediately: restartImmediately);
      }
    } catch (e) {
      _status = AutoUpdateStatus.error(e.toString());
      notifyListeners();
      rethrow;
    }
  }

  /// Normalizes and extracts the SHA-256 hex string from standard sha256sum file content.
  static String extractSha256(String content) =>
      content.trim().split(RegExp(r'\s+')).first.toLowerCase();

  /// Calculates SHA-256 hexadecimal digest for a local file.
  static Future<String> computeFileSha256(File file) async {
    final stream = file.openRead();
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }

  Future<void> _downloadUrlToFile(
    String url,
    File destination,
    int expectedSize, [
    void Function(double progress, int received, int total)? onProgress,
  ]) async {
    final client = _client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 20));
    try {
      var currentUri = Uri.parse(url);
      HttpClientResponse? response;
      int redirects = 0;

      while (redirects < 5) {
        final request = await client.getUrl(currentUri);
        request.headers.set(HttpHeaders.userAgentHeader, 'Orion-Desktop/$currentVersion');
        request.headers.set(HttpHeaders.acceptHeader, '*/*');
        request.followRedirects = false;

        response = await request.close();
        if (response.statusCode == HttpStatus.movedPermanently ||
            response.statusCode == HttpStatus.movedTemporarily ||
            response.statusCode == HttpStatus.seeOther ||
            response.statusCode == HttpStatus.temporaryRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location != null) {
            currentUri = Uri.parse(location);
            redirects++;
            continue;
          }
        }
        break;
      }

      if (response == null || response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Failed to download asset: ${response?.statusCode}',
          uri: currentUri,
        );
      }

      final contentLength = response.contentLength > 0 ? response.contentLength : expectedSize;
      final sink = destination.openWrite();
      var received = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          final progress = (received / contentLength).clamp(0.0, 1.0);
          onProgress?.call(progress, received, contentLength);
        }
      }

      await sink.flush();
      await sink.close();
    } finally {
      if (_client == null) {
        client.close(force: true);
      }
    }
  }

  Future<void> _applyWindowsUpdate(File newExe, {required bool restartImmediately}) async {
    final targetPath = targetExeOverride ??
        Platform.environment['ORION_PORTABLE_EXE'] ??
        Platform.resolvedExecutable;

    final scriptFile = File('${newExe.parent.path}${Platform.pathSeparator}apply_update.cmd');
    final batchContent = '''
@echo off
setlocal
set "ORION_PID=%~1"
set "NEW_EXE=%~2"
set "TARGET_EXE=%~3"

:WAIT_LOOP
tasklist /fi "PID eq %ORION_PID%" 2>nul | find "%ORION_PID%" >nul
if not errorlevel 1 (
    timeout /t 1 /nobreak >nul
    goto WAIT_LOOP
)
timeout /t 1 /nobreak >nul
move /y "%NEW_EXE%" "%TARGET_EXE%" >nul
start "" "%TARGET_EXE%"
del "%~f0" >nul 2>&1
''';
    await scriptFile.writeAsString(batchContent);

    if (restartImmediately) {
      await _processStarter(
        'cmd.exe',
        ['/c', scriptFile.path, '${pid}', newExe.path, targetPath],
        mode: ProcessStartMode.detached,
      );
      _exitApp(0);
    }
  }

  Future<void> _applyLinuxUpdate(File bundleFile, {required bool restartImmediately}) async {
    final isFlatpak = isFlatpakOverride?.call() ?? File('/.flatpak-info').existsSync();

    if (isFlatpak) {
      final scriptFile = File('${bundleFile.parent.path}/apply_flatpak.sh');
      final scriptContent = '''#!/bin/sh
PID="\$1"
BUNDLE="\$2"

while kill -0 "\$PID" 2>/dev/null; do
    sleep 0.5
done

flatpak-spawn --host flatpak install --user --bundle -y "\$BUNDLE"
flatpak-spawn --host flatpak run dev.snooped.orion &
rm -f "\$0"
''';
      await scriptFile.writeAsString(scriptContent);
      await Process.run('chmod', ['+x', scriptFile.path]);

      if (restartImmediately) {
        await _processStarter(
          '/bin/sh',
          [scriptFile.path, '${pid}', bundleFile.path],
          mode: ProcessStartMode.detached,
        );
        _exitApp(0);
      }
    } else {
      // Non-flatpak fallback: reveal downloaded flatpak bundle in directory
      await DesktopLauncher.revealFile(bundleFile);
    }
  }

  Future<void> _applyMacOsUpdate(
    File zipFile,
    Directory tempDir, {
    required bool restartImmediately,
  }) async {
    final extractDir = Directory('${tempDir.path}/extracted');
    if (!extractDir.existsSync()) {
      extractDir.createSync(recursive: true);
    }

    // Unzip the downloaded macOS .app bundle
    await Process.run('ditto', ['-x', '-k', zipFile.path, extractDir.path]);

    // Discover the extracted .app bundle
    String? newAppPath;
    await for (final entity in extractDir.list()) {
      if (entity.path.endsWith('.app')) {
        newAppPath = entity.path;
        break;
      }
    }
    newAppPath ??= '${extractDir.path}/orion.app';

    // Locate running .app bundle (walking upward from resolvedExecutable)
    String targetApp = '/Applications/Orion.app';
    var current = File(Platform.resolvedExecutable).parent;
    for (int i = 0; i < 5; i++) {
      if (current.path.endsWith('.app')) {
        targetApp = current.path;
        break;
      }
      current = current.parent;
    }

    final scriptFile = File('${tempDir.path}/apply_macos.sh');
    final scriptContent = '''#!/bin/sh
PID="\$1"
NEW_APP="\$2"
TARGET_APP="\$3"

while kill -0 "\$PID" 2>/dev/null; do
    sleep 0.5
done

rm -rf "\$TARGET_APP"
cp -R "\$NEW_APP" "\$TARGET_APP"
xattr -cr "\$TARGET_APP" 2>/dev/null || true
open -n "\$TARGET_APP"
rm -rf "\$(dirname "\$NEW_APP")"
rm -f "\$0"
''';
    await scriptFile.writeAsString(scriptContent);
    await Process.run('chmod', ['+x', scriptFile.path]);

    if (restartImmediately) {
      await _processStarter(
        '/bin/sh',
        [scriptFile.path, '${pid}', newAppPath, targetApp],
        mode: ProcessStartMode.detached,
      );
      _exitApp(0);
    }
  }

  void _exitApp(int code) {
    if (exitAppHandler != null) {
      exitAppHandler!(code);
    } else {
      exit(code);
    }
  }
}
