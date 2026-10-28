import 'package:flutter/foundation.dart';

/// Semantic version representation with comparison operations.
@immutable
class SemVer implements Comparable<SemVer> {
  const SemVer({
    required this.major,
    required this.minor,
    required this.patch,
    this.build,
    this.preRelease,
  });

  final int major;
  final int minor;
  final int patch;
  final String? build;
  final String? preRelease;

  /// Parses version strings such as "v1.1.2", "1.0.6+6", "v1.12", "1.0.0-hotfix".
  factory SemVer.parse(String input) {
    var raw = input.trim();
    if (raw.startsWith('v') || raw.startsWith('V')) {
      raw = raw.substring(1);
    }
    String? buildPart;
    if (raw.contains('+')) {
      final parts = raw.split('+');
      raw = parts[0];
      buildPart = parts.length > 1 ? parts[1] : null;
    }
    String? prePart;
    if (raw.contains('-')) {
      final parts = raw.split('-');
      raw = parts[0];
      prePart = parts.length > 1 ? parts.sublist(1).join('-') : null;
    }

    final segments = raw.split('.');
    final major = segments.isNotEmpty ? int.tryParse(segments[0]) ?? 0 : 0;
    final minor = segments.length > 1 ? int.tryParse(segments[1]) ?? 0 : 0;
    final patch = segments.length > 2 ? int.tryParse(segments[2]) ?? 0 : 0;

    return SemVer(
      major: major,
      minor: minor,
      patch: patch,
      build: buildPart,
      preRelease: prePart,
    );
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // Release beats pre-release with same major.minor.patch
    if (preRelease == null && other.preRelease != null) return 1;
    if (preRelease != null && other.preRelease == null) return -1;
    if (preRelease != null && other.preRelease != null) {
      final preComp = preRelease!.compareTo(other.preRelease!);
      if (preComp != 0) return preComp;
    }
    final b1 = int.tryParse(build ?? '');
    final b2 = int.tryParse(other.build ?? '');
    if (b1 != null && b2 != null) return b1.compareTo(b2);
    if (build != null && other.build != null) return build!.compareTo(other.build!);
    if (build == null && other.build != null) return -1;
    if (build != null && other.build == null) return 1;
    return 0;
  }

  bool operator >(SemVer other) => compareTo(other) > 0;
  bool operator <(SemVer other) => compareTo(other) < 0;
  bool operator >=(SemVer other) => compareTo(other) >= 0;
  bool operator <=(SemVer other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SemVer &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch &&
          build == other.build &&
          preRelease == other.preRelease;

  @override
  int get hashCode => Object.hash(major, minor, patch, build, preRelease);

  @override
  String toString() {
    final buffer = StringBuffer('$major.$minor.$patch');
    if (preRelease != null) buffer.write('-$preRelease');
    if (build != null) buffer.write('+$build');
    return buffer.toString();
  }
}

/// A downloadable asset associated with a GitHub release.
@immutable
class OrionReleaseAsset {
  const OrionReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  final String name;
  final String downloadUrl;
  final int size;

  factory OrionReleaseAsset.fromJson(Map<String, dynamic> json) =>
      OrionReleaseAsset(
        name: json['name'] as String? ?? '',
        downloadUrl: json['browser_download_url'] as String? ?? '',
        size: json['size'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'browser_download_url': downloadUrl,
    'size': size,
  };
}

/// Metadata and asset catalog for an Orion release fetched from GitHub.
@immutable
class OrionRelease {
  const OrionRelease({
    required this.tagName,
    required this.name,
    required this.publishedAt,
    required this.body,
    required this.htmlUrl,
    required this.prerelease,
    required this.assets,
    required this.semver,
  });

  final String tagName;
  final String name;
  final DateTime? publishedAt;
  final String body;
  final String htmlUrl;
  final bool prerelease;
  final List<OrionReleaseAsset> assets;
  final SemVer semver;

  String get versionTag => tagName.startsWith('v') || tagName.startsWith('V')
      ? tagName.substring(1)
      : tagName;

  OrionReleaseAsset? sha256AssetFor(OrionReleaseAsset asset) => _findAsset(
    (name) => name == '${asset.name.toLowerCase()}.sha256',
  );

  factory OrionRelease.fromJson(Map<String, dynamic> json) {
    final tagName = json['tag_name'] as String? ?? '';
    final assetList = json['assets'] as List<dynamic>? ?? const [];
    final assets = assetList
        .whereType<Map<String, dynamic>>()
        .map(OrionReleaseAsset.fromJson)
        .toList();

    return OrionRelease(
      tagName: tagName,
      name: json['name'] as String? ?? tagName,
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'] as String)
          : null,
      body: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      prerelease: json['prerelease'] as bool? ?? false,
      assets: List.unmodifiable(assets),
      semver: SemVer.parse(tagName),
    );
  }

  /// Locate Windows x64 portable executable.
  OrionReleaseAsset? get windowsAsset => _findAsset(
    (name) => name == 'orion.exe' || name.endsWith('.exe'),
  );

  /// Locate Windows sha256 checksum file.
  OrionReleaseAsset? get windowsSha256Asset => _findAsset(
    (name) => name == 'orion.exe.sha256',
  );

  /// Locate Linux Flatpak bundle.
  OrionReleaseAsset? get linuxFlatpakAsset => _findAsset(
    (name) => name.endsWith('.flatpak'),
  );

  /// Locate Linux Flatpak checksum.
  OrionReleaseAsset? get linuxSha256Asset => _findAsset(
    (name) => name.endsWith('.flatpak.sha256'),
  );

  /// Locate macOS arm64 bundle.
  OrionReleaseAsset? get macOsArm64Asset => _findAsset(
    (name) => name.contains('macos-arm64') && name.endsWith('.zip'),
  );

  /// Locate macOS arm64 checksum.
  OrionReleaseAsset? get macOsArm64Sha256Asset => _findAsset(
    (name) => name.contains('macos-arm64') && name.endsWith('.sha256'),
  );

  /// Locate macOS x86_64 bundle.
  OrionReleaseAsset? get macOsX64Asset => _findAsset(
    (name) => name.contains('macos-x86_64') && name.endsWith('.zip'),
  );

  /// Locate macOS x86_64 checksum.
  OrionReleaseAsset? get macOsX64Sha256Asset => _findAsset(
    (name) => name.contains('macos-x86_64') && name.endsWith('.sha256'),
  );

  OrionReleaseAsset? platformAsset({String? platform, String? arch}) {
    final os = (platform ?? defaultTargetPlatform.name).toLowerCase();
    if (os.contains('windows')) return windowsAsset;
    if (os.contains('linux')) return linuxFlatpakAsset;
    if (os.contains('macos') || os.contains('mac')) {
      final isArm = (arch ?? '').toLowerCase().contains('arm') ||
          (arch == null && defaultTargetPlatform == TargetPlatform.macOS);
      return isArm ? (macOsArm64Asset ?? macOsX64Asset) : (macOsX64Asset ?? macOsArm64Asset);
    }
    return null;
  }

  OrionReleaseAsset? platformSha256Asset({String? platform, String? arch}) {
    final os = (platform ?? defaultTargetPlatform.name).toLowerCase();
    if (os.contains('windows')) return windowsSha256Asset;
    if (os.contains('linux')) return linuxSha256Asset;
    if (os.contains('macos') || os.contains('mac')) {
      final isArm = (arch ?? '').toLowerCase().contains('arm') ||
          (arch == null && defaultTargetPlatform == TargetPlatform.macOS);
      return isArm
          ? (macOsArm64Sha256Asset ?? macOsX64Sha256Asset)
          : (macOsX64Sha256Asset ?? macOsArm64Sha256Asset);
    }
    return null;
  }

  /// Extracts clean changelog bullet points from markdown release notes.
  List<String> get changelogHighlights {
    final highlights = <String>[];
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trim();
      if (line.startsWith('* ') || line.startsWith('- ') || line.startsWith('• ')) {
        final text = line.substring(2).trim();
        // Remove markdown bold markers if wrapping the title
        final clean = text.replaceAll(RegExp(r'\*\*|__'), '');
        if (clean.isNotEmpty && !clean.toLowerCase().contains('full changelog')) {
          highlights.add(clean);
          if (highlights.length >= 4) break;
        }
      }
    }
    return highlights;
  }

  OrionReleaseAsset? _findAsset(bool Function(String lowercaseName) test) {
    for (final asset in assets) {
      if (test(asset.name.toLowerCase())) return asset;
    }
    return null;
  }
}

/// State stages during auto-update lifecycle.
enum AutoUpdatePhase {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  verifying,
  readyToRestart,
  error,
}

/// Snapshot of the auto-update status.
@immutable
class AutoUpdateStatus {
  const AutoUpdateStatus({
    required this.phase,
    this.release,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
    this.lastChecked,
  });

  final AutoUpdatePhase phase;
  final OrionRelease? release;
  final double progress;
  final int receivedBytes;
  final int totalBytes;
  final String? errorMessage;
  final DateTime? lastChecked;

  OrionRelease? get availableRelease => release;
  double get downloadProgress => progress;

  const AutoUpdateStatus.idle({this.lastChecked})
      : phase = AutoUpdatePhase.idle,
        release = null,
        progress = 0,
        receivedBytes = 0,
        totalBytes = 0,
        errorMessage = null;

  const AutoUpdateStatus.checking({this.lastChecked})
      : phase = AutoUpdatePhase.checking,
        release = null,
        progress = 0,
        receivedBytes = 0,
        totalBytes = 0,
        errorMessage = null;

  const AutoUpdateStatus.upToDate({required DateTime checkedAt})
      : phase = AutoUpdatePhase.upToDate,
        release = null,
        progress = 1.0,
        receivedBytes = 0,
        totalBytes = 0,
        errorMessage = null,
        lastChecked = checkedAt;

  const AutoUpdateStatus.updateAvailable(OrionRelease this.release, {required DateTime checkedAt})
      : phase = AutoUpdatePhase.updateAvailable,
        progress = 0.0,
        receivedBytes = 0,
        totalBytes = 0,
        errorMessage = null,
        lastChecked = checkedAt;

  const AutoUpdateStatus.downloading({
    required OrionRelease this.release,
    required this.progress,
    required this.receivedBytes,
    required this.totalBytes,
    this.lastChecked,
  })  : phase = AutoUpdatePhase.downloading,
        errorMessage = null;

  const AutoUpdateStatus.verifying({
    required OrionRelease this.release,
    this.lastChecked,
  })  : phase = AutoUpdatePhase.verifying,
        progress = 1.0,
        receivedBytes = 0,
        totalBytes = 0,
        errorMessage = null;

  const AutoUpdateStatus.readyToRestart({
    required OrionRelease this.release,
    this.lastChecked,
  })  : phase = AutoUpdatePhase.readyToRestart,
        progress = 1.0,
        receivedBytes = 0,
        totalBytes = 0,
        errorMessage = null;

  const AutoUpdateStatus.error(String this.errorMessage, {this.lastChecked})
      : phase = AutoUpdatePhase.error,
        release = null,
        progress = 0,
        receivedBytes = 0,
        totalBytes = 0;
}
