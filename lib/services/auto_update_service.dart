import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/auto_update_models.dart';
import 'desktop_launcher.dart';
import 'flatpak_update_service.dart';

typedef ProcessStarter =
    Future<Process> Function(
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
    FlatpakUpdateService? flatpakUpdater,
  }) : _client = client,
       currentVersion = currentVersion ?? defaultCurrentVersion,
       repoOwner = repoOwner ?? 'snooped-xl',
       repoName = repoName ?? 'Orion',
       _processStarter = processStarter ?? Process.start,
       _flatpakUpdater = flatpakUpdater ?? FlatpakUpdateService();

  /// Pinned application version reported by the desktop runtime.
  static const String defaultCurrentVersion = '1.13.8';

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
  final FlatpakUpdateService _flatpakUpdater;

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

    final client =
        _client ??
        (HttpClient()..connectionTimeout = const Duration(seconds: 15));
    try {
      final request = await client.getUrl(Uri.parse(releasesApiUrl));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Orion-Desktop/$currentVersion',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github.v3+json',
      );
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'GitHub API returned ${response.statusCode}',
          uri: Uri.parse(releasesApiUrl),
        );
      }

      final bodyString = await utf8
          .decodeStream(response)
          .timeout(const Duration(seconds: 15));
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
      _status = AutoUpdateStatus.error(
        e.toString(),
        lastChecked: lastCheckTime,
      );
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
    Future<void> Function()? beforeRestart,
  }) async {
    final platform =
        platformOverride ?? defaultTargetPlatform.name.toLowerCase();
    final asset = release.platformAsset(platform: platform, arch: archOverride);
    final checksumAsset = release.platformSha256Asset(
      platform: platform,
      arch: archOverride,
    );

    if (asset == null) {
      final message = 'No release asset available for platform: $platform';
      _status = AutoUpdateStatus.error(message);
      notifyListeners();
      throw StateError(message);
    }

    // Determine working download directory
    // Flatpak's /tmp is private and disappears with the sandbox. Its cache is
    // visible at the same absolute path on the host, including on older builds
    // without /tmp access. Unique directories also prevent concurrent writes.
    final downloadRoot =
        platform.contains('linux') &&
            (isFlatpakOverride?.call() ?? File('/.flatpak-info').existsSync())
        ? Directory(
            '${Platform.environment['XDG_CACHE_HOME'] ?? '${Platform.environment['HOME']}/.var/app/dev.snooped.orion/cache'}/orion-updates',
          )
        : Directory.systemTemp;
    await downloadRoot.create(recursive: true);
    final tempDir = platform.contains('mac')
        ? Directory(
            '${Directory.systemTemp.path}${Platform.pathSeparator}orion_update_${release.tagName}',
          )
        : await downloadRoot.createTemp('orion-update-');
    await tempDir.create(recursive: true);

    final targetDownloadFile = File(
      '${tempDir.path}${Platform.pathSeparator}${asset.name}',
    );

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

        final checksumFile = File(
          '${tempDir.path}${Platform.pathSeparator}${checksumAsset.name}',
        );
        await _downloadUrlToFile(
          checksumAsset.downloadUrl,
          checksumFile,
          checksumAsset.size,
        );

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
        await _applyWindowsUpdate(
          targetDownloadFile,
          restartImmediately: restartImmediately,
          beforeRestart: beforeRestart,
        );
      } else if (platform.contains('linux')) {
        await _applyLinuxUpdate(
          targetDownloadFile,
          expectedVersion: release.versionTag,
          restartImmediately: restartImmediately,
          beforeRestart: beforeRestart,
        );
      } else if (platform.contains('macos') || platform.contains('mac')) {
        await _applyMacOsUpdate(
          targetDownloadFile,
          tempDir,
          restartImmediately: restartImmediately,
        );
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
    final client =
        _client ??
        (HttpClient()..connectionTimeout = const Duration(seconds: 20));
    try {
      var currentUri = Uri.parse(url);
      HttpClientResponse? response;
      int redirects = 0;

      while (redirects < 5) {
        final request = await client.getUrl(currentUri);
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'Orion-Desktop/$currentVersion',
        );
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

      final contentLength = response.contentLength > 0
          ? response.contentLength
          : expectedSize;
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

  /// PowerShell literals avoid cmd expansion of %, &, ! and Unicode paths.
  static String buildWindowsUpdateScript({
    required int pid,
    required String newExePath,
    required String targetExePath,
  }) {
    String literal(String value) => "'${value.replaceAll("'", "''")}'";
    return r"""
$ErrorActionPreference = 'Stop'
$newExe = @NEW@
$targetExe = @TARGET@
$staged = $targetExe + '.orion-update'
$backup = $targetExe + '.orion-previous'
$log = Join-Path (Split-Path -Parent $newExe) 'apply_update.log'
try {
    $app = Get-Process -Id @PID@ -ErrorAction SilentlyContinue
    if ($app -and -not $app.WaitForExit(120000)) { throw 'Orion did not exit in time.' }
    Copy-Item -LiteralPath $newExe -Destination $staged -Force
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while ($true) {
        try {
            # The portable NSIS parent can outlive the Flutter process briefly.
            [IO.File]::Replace($staged, $targetExe, $backup)
            break
        } catch {
            if ([DateTime]::UtcNow -ge $deadline) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
    Start-Process -FilePath $targetExe -WorkingDirectory (Split-Path -Parent $targetExe)
    Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $newExe -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
} catch {
    $_ | Out-String | Set-Content -LiteralPath $log
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("Orion could not apply the update. Your workspace is unchanged. Details: $log", 'Orion update failed') | Out-Null
    exit 1
}
"""
        .replaceAll('@NEW@', literal(newExePath))
        .replaceAll('@TARGET@', literal(targetExePath))
        .replaceAll('@PID@', '$pid');
  }

  /// Also accepts the malformed launcher hint produced by versions <= 1.13.3.
  static String resolveWindowsUpdateTarget(String hint) {
    final lower = hint.toLowerCase();
    final nestedExe = lower.lastIndexOf('.exe\\');
    if (nestedExe >= 0) return hint.substring(0, nestedExe + 4);
    return hint;
  }

  Future<void> _applyWindowsUpdate(
    File newExe, {
    required bool restartImmediately,
    Future<void> Function()? beforeRestart,
  }) async {
    final hint =
        targetExeOverride ?? Platform.environment['ORION_PORTABLE_EXE'];
    if (hint == null || hint.trim().isEmpty) {
      throw StateError('Self-update requires the portable Orion.exe launcher.');
    }
    final targetPath = resolveWindowsUpdateTarget(hint);
    if (!await File(targetPath).exists()) {
      throw FileSystemException(
        'The original Orion.exe could not be found',
        targetPath,
      );
    }
    final scriptFile = File(
      '${newExe.parent.path}${Platform.pathSeparator}apply_update.ps1',
    );
    // Windows PowerShell 5 reads UTF-8 correctly only when it has a BOM.
    await scriptFile.writeAsString(
      '\ufeff${buildWindowsUpdateScript(pid: pid, newExePath: newExe.path, targetExePath: targetPath)}',
      flush: true,
    );

    if (restartImmediately) {
      await beforeRestart?.call();
      await _processStarter('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptFile.path,
      ], mode: ProcessStartMode.detached);
      _exitApp(0);
    }
  }

  Future<void> _applyLinuxUpdate(
    File bundleFile, {
    required String expectedVersion,
    required bool restartImmediately,
    Future<void> Function()? beforeRestart,
  }) async {
    final isFlatpak =
        isFlatpakOverride?.call() ?? File('/.flatpak-info').existsSync();
    if (!isFlatpak) {
      await DesktopLauncher.revealFile(bundleFile);
      return;
    }
    // Flatpak can deploy an update while the old sandbox is running. Await the
    // real installer result so permission/install failures leave Orion open.
    final installation = await _flatpakUpdater.install(
      bundleFile,
      expectedVersion: expectedVersion,
    );
    if (restartImmediately) {
      await beforeRestart?.call();
      await _flatpakUpdater.scheduleRestart(installation, bundleFile.parent);
      _exitApp(0);
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
        [scriptFile.path, '$pid', newAppPath, targetApp],
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
