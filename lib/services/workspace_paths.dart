import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// The writable workspace lives outside the application bundle. This is also
/// true for a mounted AppImage or a self-extracting Windows executable.
class WorkspacePaths {
  static const markerName = '.orion-workspace.json';
  static const _schema = 1;
  static const _bridgeRelative = 'scripts/Special/Orion Bridge.lua';
  static int _temporarySequence = 0;

  /// ORION_WORKSPACE is an explicit developer/automation override. XDG data
  /// directories are migration sources, never the new Linux workspace root.
  static String defaultRootPath({
    required String platform,
    required Map<String, String> environment,
    String? documentsDirectory,
  }) {
    final override = environment['ORION_WORKSPACE'];
    if (override != null && override.trim().isNotEmpty) return override;
    if (platform == 'windows') {
      if (documentsDirectory == null || documentsDirectory.isEmpty) {
        throw const FileSystemException('The Documents folder is unavailable.');
      }
      return '$documentsDirectory/orion';
    }
    final home = environment['HOME'];
    if (home == null || home.isEmpty) {
      throw const FileSystemException('The home folder is unavailable.');
    }
    return '$home/orion';
  }

  static Future<Directory> resolveDirectory() async {
    // Resolve Windows Documents with the Known Folder plugin. It can be on
    // OneDrive, another drive, or a translated/redirected location.
    final override = Platform.environment['ORION_WORKSPACE'];
    final documents = Platform.isWindows && (override?.trim().isEmpty ?? true)
        ? (await getApplicationDocumentsDirectory()).path
        : null;
    return Directory(
      defaultRootPath(
        platform: Platform.operatingSystem,
        environment: Platform.environment,
        documentsDirectory: documents,
      ),
    ).absolute;
  }

  /// Used only before controller initialization (including embedded previews).
  /// A running native controller always publishes the resolved Known Folder.
  static Directory get unresolvedDirectory {
    final environment = Platform.environment;
    final home = environment['USERPROFILE'] ?? Directory.current.path;
    return Directory(
      defaultRootPath(
        platform: Platform.operatingSystem,
        environment: {...environment, 'HOME': environment['HOME'] ?? home},
        documentsDirectory: '$home/Documents',
      ),
    );
  }

  static Future<Directory> prepare({
    Directory? directory,
    Directory? legacyDirectory,
    Future<String> Function()? bridgeSourceLoader,
  }) async {
    final root = (directory ?? await resolveDirectory()).absolute;
    await _ensureDirectory(root);
    for (final child in [
      'scripts',
      'scripts/Special',
      'autoexec',
      'themes',
      'cache',
      'backups',
    ]) {
      await _ensureDirectory(Directory('${root.path}/$child'));
    }

    final marker = File('${root.path}/$markerName');
    await _requireRegularOrMissing(marker.path);
    Map<String, dynamic>? installed;
    if (await marker.exists()) {
      try {
        final value = jsonDecode(await marker.readAsString());
        if (value is Map<String, dynamic>) installed = value;
      } on FormatException {
        // A partial marker is retried; it never resets the user's workspace.
      }
    }

    if (installed?['schema'] != _schema) {
      var legacy = legacyDirectory;
      if (legacy == null &&
          !Platform.environment.containsKey('ORION_WORKSPACE')) {
        try {
          legacy = await getApplicationSupportDirectory();
        } on Object {
          // A first installation has no old support folder to migrate.
        }
      }
      if (legacy != null && legacy.absolute.path != root.path) {
        await _migrate(legacy.absolute, root);
      }
    }

    final source =
        await (bridgeSourceLoader ??
            () => rootBundle.loadString('assets/bridge/Orion Bridge.lua'))();
    final revision = _fingerprint(source);
    final bridge = File('${root.path}/$_bridgeRelative');
    await _requireRegularOrMissing(bridge.path);
    final revisionChanged =
        installed?['schema'] != _schema ||
        installed?['bridgeRevision'] != revision;
    if (revisionChanged || !await bridge.exists()) {
      if (await bridge.exists() && await bridge.readAsString() != source) {
        await _backup(bridge, root, 'Orion Bridge');
      }
      await _replaceFile(bridge, source);
    }
    if (revisionChanged) {
      await _replaceFile(
        marker,
        jsonEncode({'schema': _schema, 'bridgeRevision': revision}),
      );
    }
    return root;
  }

  static Future<void> _ensureDirectory(Directory directory) async {
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'The workspace path must be a regular directory',
        directory.path,
      );
    }
    await directory.create(recursive: true);
  }

  static Future<void> _requireRegularOrMissing(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException(
        'The workspace file must be a regular file',
        path,
      );
    }
  }

  static Future<void> _replaceFile(File target, String content) async {
    await _requireRegularOrMissing(target.path);
    final temporary = File(
      '${target.path}.provisioning-$pid-${DateTime.now().microsecondsSinceEpoch}-${_temporarySequence++}.tmp',
    );
    await temporary.create(exclusive: true);
    try {
      await temporary.writeAsString(content, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static Future<void> _backup(File source, Directory root, String name) async {
    final destination = File(
      '${root.path}/backups/$name-${DateTime.now().microsecondsSinceEpoch}.lua',
    );
    await source.copy(destination.path);
  }

  static Future<void> _migrate(Directory legacy, Directory root) async {
    if (await FileSystemEntity.type(legacy.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    final oldState = File('${legacy.path}/orion-workspace.json');
    final state = File('${root.path}/orion-workspace.json');
    await _requireRegularOrMissing(state.path);
    if (!await state.exists() &&
        await FileSystemEntity.type(oldState.path, followLinks: false) ==
            FileSystemEntityType.file) {
      var content = await oldState.readAsString();
      try {
        content = jsonEncode(_remapState(jsonDecode(content), legacy, root));
      } on FormatException {
        // Preserve a damaged profile for the normal recovery handling.
      }
      await _replaceFile(state, content);
    }
    final visited = <String>{};
    for (final pair in {
      'scripts': 'scripts',
      'Scripts': 'scripts',
      'autoexec': 'autoexec',
      'AutoExec': 'autoexec',
      'themes': 'themes',
    }.entries) {
      final source = Directory('${legacy.path}/${pair.key}');
      final identity = Platform.isWindows
          ? source.path.toLowerCase()
          : source.path;
      if (!visited.add(identity)) continue;
      await _mergeDirectory(source, Directory('${root.path}/${pair.value}'));
    }
  }

  static Object? _remapState(
    Object? value,
    Directory legacy,
    Directory root, [
    String? key,
  ]) {
    if (value is Map) {
      return value.map(
        (key, value) =>
            MapEntry(key, _remapState(value, legacy, root, key.toString())),
      );
    }
    if (value is List) {
      return value.map((item) => _remapState(item, legacy, root)).toList();
    }
    if (value is String &&
        {'filePath', 'scriptsDirectory', 'scriptPath'}.contains(key)) {
      final prefix = '${legacy.path}${Platform.pathSeparator}';
      if (value.startsWith(prefix)) {
        var relative = value.substring(prefix.length).replaceAll('\\', '/');
        if (relative == 'Scripts' || relative.startsWith('Scripts/')) {
          relative = 'scripts${relative.substring(7)}';
        }
        if (relative == 'AutoExec' || relative.startsWith('AutoExec/')) {
          relative = 'autoexec${relative.substring(8)}';
        }
        return '${root.path}/$relative';
      }
    }
    return value;
  }

  static Future<void> _mergeDirectory(
    Directory source,
    Directory destination,
  ) async {
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    await _ensureDirectory(destination);
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      final target = '${destination.path}/$name';
      if (entity is Directory) {
        await _mergeDirectory(entity, Directory(target));
      } else if (entity is File) {
        await _requireRegularOrMissing(target);
        if (!await File(target).exists()) await entity.copy(target);
      }
      // Links are deliberately not copied or followed into a user workspace.
    }
  }

  static String _fingerprint(String source) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(source)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return '${source.length}:${hash.toRadixString(16)}';
  }
}
