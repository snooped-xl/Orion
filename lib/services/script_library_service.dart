import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/local_script.dart';
import 'file_paths.dart';

/// Owns the user's filesystem library, independently of open editor tabs.
/// Linux inotify is not recursive, so each visible directory has its own watch.
class ScriptLibraryService extends ChangeNotifier {
  ScriptLibraryService({
    required Directory directory,
    Future<String> Function()? bridgeSourceLoader,
  }) : directory = directory.absolute,
       _bridgeSourceLoader =
           bridgeSourceLoader ??
           (() => rootBundle.loadString('assets/bridge/Orion Bridge.lua'));

  final Directory directory;
  final Future<String> Function() _bridgeSourceLoader;
  static const _metadataName = '.orion-codes.json';
  static const _bridgePath = 'Special/Orion Bridge.lua';
  final _disposeSignal = Completer<void>();
  final Map<String, _LibraryWatch> _watchers = {};
  Map<String, ScriptColorCode> _codes = {};
  List<LocalScriptEntry> _entries = const [];
  Future<void>? _initializeFuture;
  Future<void>? _refreshFuture;
  Future<void> _mutationTail = Future.value();
  Timer? _debounce;
  bool _started = false,
      _disposed = false,
      _loading = false,
      _refreshAgain = false;
  String? _error;
  String? _watchIssue;
  int _codeRevision = 0, _temporaryCounter = 0;

  List<LocalScriptEntry> get entries => _entries;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> initialize() {
    if (_disposed) return Future.value();
    _started = true;
    return _initializeFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    String? initializationError;
    try {
      final rootType = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (rootType == FileSystemEntityType.link) {
        throw FileSystemException(
          'The script library cannot be a symbolic link',
          directory.path,
        );
      }
      if (_disposed) return;
      await directory.create(recursive: true);
      await _ensureParents('Special/placeholder.lua');
      final type = await _targetType(_bridgePath);
      if (type == FileSystemEntityType.notFound) {
        final source = await Future.any<String>([
          _bridgeSourceLoader(),
          _disposeSignal.future.then<String>(
            (_) => throw StateError('Library disposed'),
          ),
        ]);
        if (_disposed) return;
        // Exclusive creation prevents an existing/custom bridge being replaced.
        try {
          await _createFile(_bridgePath, source);
        } on PathExistsException {
          // A file created externally while the asset loaded belongs to the user.
        }
      } else if (type != FileSystemEntityType.file) {
        throw FileSystemException(
          'The bridge path is not a regular file',
          _absolute(_bridgePath),
        );
      }
    } on FileSystemException catch (failure) {
      initializationError = failure.message;
    } on FlutterError catch (failure) {
      initializationError = failure.message;
    } on StateError {
      if (_disposed) return;
      rethrow;
    } on Exception catch (failure) {
      if (!_disposed) initializationError = failure.toString();
    }
    if (_disposed) return;
    await refresh();
    if (!_disposed && initializationError != null) {
      _error = 'Could not initialize scripts: $initializationError';
      notifyListeners();
    }
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    if (!_started) return initialize();
    if (_refreshFuture != null) {
      _refreshAgain = true;
      return _refreshFuture!;
    }
    final done = Completer<void>();
    _refreshFuture = done.future;
    unawaited(_drainRefresh(done));
    return done.future;
  }

  Future<void> _drainRefresh(Completer<void> done) async {
    _loading = true;
    notifyListeners();
    try {
      do {
        _refreshAgain = false;
        if (!_disposed) await _scan();
      } while (_refreshAgain && !_disposed);
    } finally {
      _refreshFuture = null;
      _loading = false;
      if (!_disposed) notifyListeners();
      done.complete();
    }
  }

  Future<void> _scan() async {
    _watchIssue = null;
    final issues = <String>[];
    final revision = _codeRevision;
    try {
      final loaded = await _readCodes();
      if (_disposed) return;
      if (revision == _codeRevision) _codes = loaded;
    } on FileSystemException catch (failure) {
      issues.add('Could not read colour codes: ${failure.message}');
    } on FormatException catch (failure) {
      issues.add('Could not read colour codes: ${failure.message}');
    }
    final found = <LocalScriptEntry>[];
    final directories = <String>{};
    try {
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.directory) {
        if (type == FileSystemEntityType.link) _entries = const [];
        throw FileSystemException(
          'The script library is not a regular directory',
          directory.path,
        );
      }
      await _walk(directory, '', found, directories, issues);
      if (_disposed) return;
      found.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.relativePath.compareTo(b.relativePath);
      });
      _entries = List.unmodifiable(found);
    } on FileSystemException catch (failure) {
      issues.add('Could not read scripts: ${failure.message}');
    }
    if (_disposed) return;
    // Watching the parent also notices deletion/recreation of the scripts root.
    directories.add(directory.parent.path);
    await _reconcileWatches(directories, issues);
    if (_watchIssue != null) issues.add(_watchIssue!);
    if (!_disposed) _error = issues.isEmpty ? null : issues.join('\n');
  }

  Future<void> _walk(
    Directory folder,
    String prefix,
    List<LocalScriptEntry> found,
    Set<String> directories,
    List<String> issues,
  ) async {
    directories.add(folder.path);
    try {
      await for (final entity in folder.list(followLinks: false)) {
        if (_disposed) return;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.')) continue;
        final relative = prefix.isEmpty ? name : '$prefix/$name';
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.directory) {
          found.add(_entry(relative, isDirectory: true));
          await _walk(
            Directory(entity.path),
            relative,
            found,
            directories,
            issues,
          );
        } else if (type == FileSystemEntityType.file && _supported(name)) {
          found.add(_entry(relative, isDirectory: false));
        }
      }
    } on FileSystemException catch (failure) {
      issues.add(
        'Could not read ${prefix.isEmpty ? 'scripts' : prefix}: ${failure.message}',
      );
      // Keep the last known subtree when a folder is temporarily unreadable.
      final existing = found.map((entry) => entry.relativePath).toSet();
      for (final previous in _entries) {
        if ((prefix.isEmpty || previous.relativePath.startsWith('$prefix/')) &&
            existing.add(previous.relativePath)) {
          found.add(
            _entry(previous.relativePath, isDirectory: previous.isDirectory),
          );
          if (previous.isDirectory) directories.add(previous.path);
        }
      }
    }
  }

  LocalScriptEntry _entry(String relative, {required bool isDirectory}) =>
      LocalScriptEntry(
        relativePath: relative,
        name: relative.split('/').last,
        path: _absolute(relative),
        isDirectory: isDirectory,
        code: _resolveCode(relative),
      );

  ScriptColorCode _resolveCode(String relative) {
    var current = relative;
    while (true) {
      if (_codes.containsKey(current)) return _codes[current]!;
      if (current == 'Special') return ScriptColorCode.special;
      final slash = current.lastIndexOf('/');
      if (slash < 0) return ScriptColorCode.none;
      current = current.substring(0, slash);
    }
  }

  Future<LocalScriptEntry> createScript(
    String relativePath, {
    String content = '',
  }) async {
    final relative = _validateRelative(relativePath);
    if (!_supported(relative)) {
      throw ArgumentError('Use a .lua, .luau or .txt filename');
    }
    await initialize();
    return _mutate(() async {
      await _ensureParents(relative);
      await _createFile(relative, content);
      await refresh();
      return _entry(relative, isDirectory: false);
    });
  }

  Future<void> setCode(String relativePath, ScriptColorCode code) async {
    final relative = _validateRelative(relativePath);
    await initialize();
    await _mutate(() async {
      final type = await _targetType(relative);
      if (type != FileSystemEntityType.directory &&
          (type != FileSystemEntityType.file || !_supported(relative))) {
        throw FileSystemException(
          'The script or folder no longer exists',
          _absolute(relative),
        );
      }
      // Read the latest atomic metadata before updating one key, preserving
      // edits made by another instance or an external editor.
      final latest = await _readCodes();
      latest[relative] = code;
      await _writeCodes(latest);
      if (_disposed) return;
      _codes = latest;
      _codeRevision++;
      await refresh();
    });
  }

  Future<T> _mutate<T>(Future<T> Function() operation) {
    final result = _mutationTail.then((_) async {
      if (_disposed) throw StateError('The script library is disposed');
      try {
        return await operation();
      } on FileSystemException catch (failure) {
        if (!_disposed) {
          _error = failure.message;
          notifyListeners();
        }
        rethrow;
      } on FormatException catch (failure) {
        if (!_disposed) {
          _error = failure.message;
          notifyListeners();
        }
        rethrow;
      }
    });
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _createFile(String relative, String content) async {
    await _targetType(relative);
    if (_disposed) throw StateError('The script library is disposed');
    final file = File(_absolute(relative));
    await file.create(exclusive: true);
    // Finish a file we have exclusively created, even if its view closes now.
    // Leaving an empty bridge would prevent its seed from being retried later.
    await file.writeAsString(content, flush: true);
  }

  Future<void> _ensureParents(String relative) async {
    final parts = relative.split('/');
    for (var i = 1; i < parts.length; i++) {
      if (_disposed) throw StateError('The script library is disposed');
      final parent = parts.take(i).join('/');
      final type = await _targetType(parent);
      if (type == FileSystemEntityType.notFound) {
        await Directory(_absolute(parent)).create();
      } else if (type != FileSystemEntityType.directory) {
        throw FileSystemException(
          'A parent is not a directory',
          _absolute(parent),
        );
      }
    }
  }

  Future<FileSystemEntityType> _targetType(String relative) async {
    final rootType = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (rootType != FileSystemEntityType.directory) {
      throw FileSystemException(
        'The script library is not a regular directory',
        directory.path,
      );
    }
    var current = directory.path;
    var type = rootType;
    final parts = relative.split('/');
    for (var i = 0; i < parts.length; i++) {
      current = '$current${Platform.pathSeparator}${parts[i]}';
      type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw FileSystemException(
          'Symbolic links are not supported in the script library',
          current,
        );
      }
      if (i < parts.length - 1 &&
          type != FileSystemEntityType.directory &&
          type != FileSystemEntityType.notFound) {
        throw FileSystemException('A parent is not a directory', current);
      }
    }
    return type;
  }

  Future<Map<String, ScriptColorCode>> _readCodes() async {
    final file = File(_absolute(_metadataName));
    final type = await _targetType(_metadataName);
    if (type == FileSystemEntityType.notFound) return {};
    if (type != FileSystemEntityType.file) {
      throw FileSystemException(
        'Colour metadata is not a regular file',
        file.path,
      );
    }
    if (await file.length() > 2 * 1024 * 1024) {
      throw const FormatException('Colour metadata is too large');
    }
    final json = jsonDecode(await file.readAsString());
    if (json is! Map || json['version'] != 1 || json['codes'] is! Map) {
      throw const FormatException('Invalid colour metadata');
    }
    final result = <String, ScriptColorCode>{};
    for (final entry in (json['codes'] as Map).entries) {
      if (entry.key is! String || entry.value is! String) continue;
      final matches = ScriptColorCode.values.where(
        (code) => code.name == entry.value,
      );
      if (matches.isEmpty) continue;
      try {
        result[_validateRelative(entry.key as String)] = matches.first;
      } on ArgumentError {
        // A malformed metadata key can never redirect a filesystem operation.
      }
    }
    return result;
  }

  Future<void> _writeCodes(Map<String, ScriptColorCode> codes) async {
    await _targetType(_metadataName);
    final temporary = File(
      _absolute(
        '.orion-codes.${DateTime.now().microsecondsSinceEpoch}.${_temporaryCounter++}.tmp',
      ),
    );
    try {
      await temporary.create(exclusive: true);
      await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'codes': codes.map((path, code) => MapEntry(path, code.name)),
        }),
        flush: true,
      );
      if (_disposed) return;
      await _targetType(_metadataName);
      await temporary.rename(_absolute(_metadataName));
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  String _absolute(String relative) =>
      '${directory.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';

  static bool _supported(String path) =>
      const ['.lua', '.luau', '.txt'].any(path.toLowerCase().endsWith);

  static String _validateRelative(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains('\\') ||
        RegExp(r'^[a-zA-Z]:|[\x00-\x1f\x7f]').hasMatch(path) ||
        (Platform.isWindows &&
            path
                .split('/')
                .any((part) => !FilePaths.validWindowsComponent(part))) ||
        path
            .split('/')
            .any((part) => part.trim().isEmpty || part.startsWith('.'))) {
      throw ArgumentError.value(
        path,
        'relativePath',
        'Use a visible relative path with valid filenames and without traversal',
      );
    }
    return path;
  }

  Future<void> _reconcileWatches(Set<String> paths, List<String> issues) async {
    for (final stale
        in _watchers.keys
            .where((path) => !paths.contains(path) || _watchers[path]!.failed)
            .toList()) {
      final watcher = _watchers.remove(stale)!;
      await watcher.subscription?.cancel();
    }
    for (final path in paths) {
      if (_disposed || _watchers.containsKey(path)) continue;
      final watcher = _LibraryWatch();
      try {
        if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        if (_disposed) return;
        _watchers[path] = watcher;
        watcher.subscription = Directory(path).watch().listen(
          (event) {
            if (FilePaths.same(path, directory.parent.path) &&
                !FilePaths.same(event.path, directory.path)) {
              return;
            }
            final name = event.path.split(Platform.pathSeparator).last;
            if (name.startsWith('.') && name != _metadataName) return;
            _scheduleRefresh();
          },
          onError: (Object failure) {
            watcher.failed = true;
            if (!_disposed) {
              _watchIssue = 'Could not watch scripts: $failure';
              _error = _watchIssue;
              notifyListeners();
            }
          },
          onDone: () {
            if (identical(_watchers[path], watcher)) _watchers.remove(path);
            if (!watcher.failed) _scheduleRefresh();
          },
        );
      } on FileSystemException catch (failure) {
        _watchers.remove(path);
        issues.add('Could not watch scripts: ${failure.message}');
      } on UnsupportedError catch (failure) {
        _watchers.remove(path);
        issues.add('Could not watch scripts: ${failure.message}');
      }
    }
  }

  void _scheduleRefresh() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      _debounce = null;
      unawaited(refresh());
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _disposeSignal.complete();
    _debounce?.cancel();
    for (final watcher in _watchers.values) {
      unawaited(watcher.subscription?.cancel().catchError((Object _) {}));
    }
    _watchers.clear();
    super.dispose();
  }
}

class _LibraryWatch {
  StreamSubscription<FileSystemEvent>? subscription;
  bool failed = false;
}
