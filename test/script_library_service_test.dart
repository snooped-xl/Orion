import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/local_script.dart';
import 'package:orion/services/file_paths.dart';
import 'package:orion/services/script_library_service.dart';

void main() {
  late Directory temporary;
  late Directory scripts;
  late List<ScriptLibraryService> services;

  ScriptLibraryService library({Future<String> Function()? loader}) {
    final service = ScriptLibraryService(
      directory: scripts,
      bridgeSourceLoader: loader ?? (() async => 'print("packaged bridge")\n'),
    );
    services.add(service);
    return service;
  }

  LocalScriptEntry entry(ScriptLibraryService service, String path) =>
      service.entries.singleWhere((item) => item.relativePath == path);

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('orion-script-library-');
    scripts = Directory('${temporary.path}/scripts');
    services = [];
  });
  tearDown(() async {
    for (final service in services) {
      service.dispose();
    }
    await temporary.delete(recursive: true);
  });

  test(
    'initializes dedicated folder and seeds special bridge exactly once',
    () async {
      var loads = 0;
      final service = library(
        loader: () async {
          loads++;
          return 'print("bridge source")\n';
        },
      );
      await service.initialize();
      await service.initialize();
      expect(await scripts.exists(), isTrue);
      expect(service.loading, isFalse);
      expect(service.error, isNull);
      expect(loads, 1);
      expect(entry(service, 'Special').isDirectory, isTrue);
      expect(entry(service, 'Special').code, ScriptColorCode.special);
      final bridge = entry(service, 'Special/Orion Bridge.lua');
      expect(bridge.name, 'Orion Bridge.lua');
      expect(
        FilePaths.same(bridge.path, '${scripts.path}/Special/Orion Bridge.lua'),
        isTrue,
      );
      expect(bridge.code, ScriptColorCode.special);
      expect(
        await File(bridge.path).readAsString(),
        'print("bridge source")\n',
      );
      expect(() => service.entries.clear(), throwsUnsupportedError);
    },
  );

  test(
    'existing custom bridge is never replaced or needlessly loaded',
    () async {
      final file = File('${scripts.path}/Special/Orion Bridge.lua');
      await file.parent.create(recursive: true);
      await file.writeAsString('-- my modified bridge');
      final service = library(loader: () => throw StateError('must not load'));
      await service.initialize();
      expect(await file.readAsString(), '-- my modified bridge');
      expect(service.error, isNull);
    },
  );

  test(
    'bridge created while source loads wins the exclusive seed race',
    () async {
      final entered = Completer<void>();
      final source = Completer<String>();
      final service = library(
        loader: () {
          entered.complete();
          return source.future;
        },
      );
      final ready = service.initialize();
      await entered.future;
      final file = File('${scripts.path}/Special/Orion Bridge.lua');
      await file.writeAsString('-- external bridge');
      source.complete('-- packaged bridge');
      await ready;
      expect(await file.readAsString(), '-- external bridge');
      expect(service.error, isNull);
    },
  );

  test(
    'recursively scans supported files, sorts folders first and skips links/hidden',
    () async {
      await Directory('${scripts.path}/Nested').create(recursive: true);
      await Directory('${scripts.path}/Empty').create();
      await Directory('${scripts.path}/.hidden').create();
      for (final path in [
        'Alpha.LUA',
        'Nested/Beta.luau',
        'readme.txt',
        'ignored.png',
        '.hidden/secret.lua',
        '.private.lua',
      ]) {
        await File('${scripts.path}/$path').writeAsString(path);
      }
      final outside = Directory('${temporary.path}/outside');
      await outside.create();
      await File('${outside.path}/outside.lua').writeAsString('-- outside');
      if (await _tryCreateLink('${scripts.path}/linked-folder', outside.path)) {
        await Link(
          '${scripts.path}/linked.lua',
        ).create('${outside.path}/outside.lua');
      }
      final service = library();
      await service.initialize();
      expect(service.entries.map((item) => item.relativePath), [
        'Empty',
        'Nested',
        'Special',
        'Alpha.LUA',
        'Nested/Beta.luau',
        'Special/Orion Bridge.lua',
        'readme.txt',
      ]);
      expect(
        service.entries.every((item) => !item.relativePath.contains('\\')),
        isTrue,
      );
    },
  );

  test(
    'creates nested script on disk and returns its independent library entry',
    () async {
      final service = library();
      final created = await service.createScript(
        'Utilities/hello.luau',
        content: '  print("hello")\n',
      );
      expect(created.relativePath, 'Utilities/hello.luau');
      expect(created.name, 'hello.luau');
      expect(created.isDirectory, isFalse);
      expect(created.code, ScriptColorCode.none);
      expect(await File(created.path).readAsString(), '  print("hello")\n');
      expect(entry(service, 'Utilities').isDirectory, isTrue);
      expect(entry(service, created.relativePath), created);
    },
  );

  test(
    'concurrent duplicate creates never overwrite the winning script',
    () async {
      final service = library();
      await service.initialize();
      final first = service.createScript('same.lua', content: 'first');
      final second = service.createScript('same.lua', content: 'second');
      await expectLater(second, throwsA(isA<PathExistsException>()));
      final winner = await first;
      expect(await File(winner.path).readAsString(), 'first');
      expect(service.error, isNotNull);
    },
  );

  test(
    'persists folder colours and explicit none overrides Special inheritance',
    () async {
      final service = library();
      await service.createScript('Special/Nested/a.lua');
      await service.createScript('Special/b.lua');
      await service.createScript('Tools/c.lua');
      expect(
        entry(service, 'Special/Nested/a.lua').code,
        ScriptColorCode.special,
      );
      await service.setCode('Special/Nested/a.lua', ScriptColorCode.none);
      await service.setCode('Special', ScriptColorCode.blue);
      await service.setCode('Tools', ScriptColorCode.red);
      expect(entry(service, 'Special/Nested/a.lua').code, ScriptColorCode.none);
      expect(entry(service, 'Special/b.lua').code, ScriptColorCode.blue);
      expect(
        entry(service, 'Special/Orion Bridge.lua').code,
        ScriptColorCode.blue,
      );
      expect(entry(service, 'Tools/c.lua').code, ScriptColorCode.red);
      final metadata =
          jsonDecode(
                await File('${scripts.path}/.orion-codes.json').readAsString(),
              )
              as Map;
      expect((metadata['codes'] as Map)['Special/Nested/a.lua'], 'none');
      expect(
        await scripts
            .list()
            .where((item) => item.path.endsWith('.tmp'))
            .isEmpty,
        isTrue,
      );
      service.dispose();
      final restored = library();
      await restored.initialize();
      expect(
        entry(restored, 'Special/Nested/a.lua').code,
        ScriptColorCode.none,
      );
      expect(entry(restored, 'Tools/c.lua').code, ScriptColorCode.red);
      await restored.setCode('Special', ScriptColorCode.special);
      expect(entry(restored, 'Special/b.lua').code, ScriptColorCode.special);
    },
  );

  test('serialized colour changes preserve every independent key', () async {
    final service = library();
    await service.createScript('a.lua');
    await service.createScript('b.lua');
    await Future.wait([
      service.setCode('a.lua', ScriptColorCode.white),
      service.setCode('b.lua', ScriptColorCode.green),
    ]);
    expect(entry(service, 'a.lua').code, ScriptColorCode.white);
    expect(entry(service, 'b.lua').code, ScriptColorCode.green);
  });

  test(
    'manual refresh observes external additions/deletion and code metadata',
    () async {
      final service = library();
      await service.initialize();
      final external = File('${scripts.path}/external.lua');
      await external.writeAsString('-- external');
      await File('${scripts.path}/.orion-codes.json').writeAsString(
        jsonEncode({
          'version': 1,
          'codes': {'external.lua': 'green', '../unsafe.lua': 'red'},
        }),
      );
      await service.refresh();
      expect(entry(service, 'external.lua').code, ScriptColorCode.green);
      await external.delete();
      await service.refresh();
      expect(
        service.entries.any((item) => item.relativePath == 'external.lua'),
        isFalse,
      );
    },
  );

  test(
    'Linux watchers observe existing nested folders and discover new folder watches',
    () async {
      await Directory(
        '${scripts.path}/Existing/Nested',
      ).create(recursive: true);
      final service = library();
      await service.initialize();
      await File(
        '${scripts.path}/Existing/Nested/external.lua',
      ).writeAsString('first');
      await _eventually(
        () => service.entries.any(
          (item) => item.relativePath == 'Existing/Nested/external.lua',
        ),
      );
      final added = Directory('${scripts.path}/New Folder');
      await added.create();
      await _eventually(
        () => service.entries.any((item) => item.relativePath == 'New Folder'),
      );
      await File('${added.path}/later.txt').writeAsString('later');
      await _eventually(
        () => service.entries.any(
          (item) => item.relativePath == 'New Folder/later.txt',
        ),
      );
      await File('${added.path}/later.txt').delete();
      await _eventually(
        () => !service.entries.any(
          (item) => item.relativePath == 'New Folder/later.txt',
        ),
      );
    },
  );

  test(
    'parent watch recovers after scripts root is deleted and recreated',
    () async {
      final service = library();
      await service.initialize();
      await scripts.delete(recursive: true);
      await scripts.create();
      await File('${scripts.path}/returned.lua').writeAsString('restored');
      await _eventually(
        () =>
            service.entries.any((item) => item.relativePath == 'returned.lua'),
      );
      await File('${scripts.path}/later.lua').writeAsString('watched again');
      await _eventually(
        () => service.entries.any((item) => item.relativePath == 'later.lua'),
      );
    },
  );

  test(
    'temporarily unreadable child keeps its previous subtree and recovers',
    () async {
      final service = library();
      await service.createScript('Private/known.lua', content: '-- keep');
      final deniedPath = '${scripts.path}/Private';
      await IOOverrides.runWithIOOverrides(
        () => service.refresh(),
        _DeniedListingOverrides(deniedPath),
      );
      expect(entry(service, 'Private/known.lua').name, 'known.lua');
      expect(service.error, contains('Private'));
      await service.refresh();
      expect(service.error, isNull);
      expect(entry(service, 'Private/known.lua').name, 'known.lua');
    },
  );

  test(
    'watch errors remain visible and a manual refresh recovers watching',
    () async {
      final service = library();
      await IOOverrides.runWithIOOverrides(
        () => service.initialize(),
        _FailedWatchOverrides(scripts.path),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(service.error, contains('watch'));
      await service.refresh();
      expect(service.error, isNull);
      await File('${scripts.path}/recovered.lua').writeAsString('-- watched');
      await _eventually(
        () =>
            service.entries.any((item) => item.relativePath == 'recovered.lua'),
      );
    },
  );

  test(
    'invalid paths and unsupported extensions cannot escape or create hidden files',
    () async {
      final service = library();
      for (final path in [
        '',
        '../outside.lua',
        '/absolute.lua',
        'C:/outside.lua',
        r'folder\escape.lua',
        'folder/../escape.lua',
        '.secret.lua',
        'x/.hidden/a.lua',
        'x//a.lua',
        'x/./a.lua',
        'x/a\n.lua',
        'no-extension',
        'picture.png',
      ]) {
        await expectLater(
          service.createScript(path),
          throwsArgumentError,
          reason: path,
        );
      }
      expect(await scripts.exists(), isFalse);
      await service.initialize();
      await expectLater(
        service.setCode('../outside.lua', ScriptColorCode.red),
        throwsArgumentError,
      );
      await expectLater(
        service.setCode('missing.lua', ScriptColorCode.red),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'script, parent folder and metadata symbolic links are never followed',
    () async {
      final service = library();
      await service.initialize();
      final outside = Directory('${temporary.path}/outside');
      await outside.create();
      final external = File('${outside.path}/untouched.lua');
      await external.writeAsString('-- untouched');
      if (!await _tryCreateLink('${scripts.path}/linked', outside.path)) {
        markTestSkipped('Windows symlink creation privilege is unavailable.');
        return;
      }
      await Link('${scripts.path}/linked.lua').create(external.path);
      await expectLater(
        service.createScript('linked/new.lua'),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        service.createScript('linked.lua', content: 'overwrite'),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        service.setCode('linked.lua', ScriptColorCode.red),
        throwsA(isA<FileSystemException>()),
      );
      await Link('${scripts.path}/.orion-codes.json').create(external.path);
      await expectLater(
        service.setCode('Special', ScriptColorCode.red),
        throwsA(isA<FileSystemException>()),
      );
      expect(await external.readAsString(), '-- untouched');
      expect(await File('${outside.path}/new.lua').exists(), isFalse);
      await service.refresh();
      expect(
        service.entries.any((item) => item.relativePath.startsWith('linked')),
        isFalse,
      );
    },
  );

  test(
    'symlink Special is not seeded and initialize reports IO failure without throwing',
    () async {
      await scripts.create();
      final outside = Directory('${temporary.path}/outside');
      await outside.create();
      if (!await _tryCreateLink('${scripts.path}/Special', outside.path)) {
        markTestSkipped('Windows symlink creation privilege is unavailable.');
        return;
      }
      final service = library();
      await service.initialize();
      expect(service.error, isNotNull);
      expect(service.entries, isEmpty);
      expect(await File('${outside.path}/Orion Bridge.lua').exists(), isFalse);
    },
  );

  test(
    'malformed metadata reports error and preserves last known colours',
    () async {
      final service = library();
      await service.createScript('a.lua');
      await service.setCode('a.lua', ScriptColorCode.red);
      final metadata = File('${scripts.path}/.orion-codes.json');
      await metadata.writeAsString('{ broken');
      await service.refresh();
      expect(service.error, contains('colour codes'));
      expect(entry(service, 'a.lua').code, ScriptColorCode.red);
      await metadata.delete();
      await service.refresh();
      expect(service.error, isNull);
      expect(entry(service, 'a.lua').code, ScriptColorCode.none);
    },
  );

  test(
    'initialize failure on an unusable root is exposed without failing startup',
    () async {
      await File(scripts.path).writeAsString('not a directory');
      final service = library();
      await service.initialize();
      expect(service.error, isNotNull);
      expect(service.loading, isFalse);
      expect(service.entries, isEmpty);
    },
  );

  test(
    'refresh requests coalesce and disposal cancels slow initialization promptly',
    () async {
      final service = library();
      await service.initialize();
      final requests = List.generate(20, (_) => service.refresh());
      expect(
        requests.every((future) => identical(future, requests.first)),
        isTrue,
      );
      await Future.wait(requests);
      final entered = Completer<void>();
      final blocked = Completer<String>();
      final delayedDirectory = Directory('${temporary.path}/delayed');
      final delayed = ScriptLibraryService(
        directory: delayedDirectory,
        bridgeSourceLoader: () {
          entered.complete();
          return blocked.future;
        },
      );
      services.add(delayed);
      final ready = delayed.initialize();
      await entered.future;
      var notifications = 0;
      delayed.addListener(() => notifications++);
      delayed.dispose();
      await ready.timeout(const Duration(seconds: 1));
      await delayed.refresh();
      blocked.complete('-- too late');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifications, 0);
      expect(
        await File(
          '${delayedDirectory.path}/Special/Orion Bridge.lua',
        ).exists(),
        isFalse,
      );
      await expectLater(delayed.createScript('late.lua'), throwsStateError);
    },
  );

  test(
    'dispose closes watches and no later filesystem event notifies listeners',
    () async {
      final service = library();
      await service.initialize();
      var notifications = 0;
      service.addListener(() => notifications++);
      service.dispose();
      service.dispose();
      await File('${scripts.path}/after.lua').writeAsString('after');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(notifications, 0);
      expect(
        service.entries.any((item) => item.relativePath == 'after.lua'),
        isFalse,
      );
    },
  );
}

Future<void> _eventually(bool Function() predicate) async {
  final limit = DateTime.now().add(const Duration(seconds: 4));
  while (!predicate()) {
    if (DateTime.now().isAfter(limit)) {
      fail('Filesystem watcher did not refresh the library');
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

Future<bool> _tryCreateLink(String path, String target) async {
  try {
    await Link(path).create(target);
    return true;
  } on FileSystemException catch (error) {
    if (Platform.isWindows && error.osError?.errorCode == 1314) return false;
    rethrow;
  }
}

final class _DeniedListingOverrides extends IOOverrides {
  _DeniedListingOverrides(this.deniedPath);
  final String deniedPath;
  @override
  Directory createDirectory(String path) {
    final directory = super.createDirectory(path);
    return FilePaths.same(path, deniedPath)
        ? _DeniedDirectory(directory)
        : directory;
  }
}

class _DeniedDirectory implements Directory {
  _DeniedDirectory(this.delegate);
  final Directory delegate;
  @override
  String get path => delegate.path;
  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => Stream.error(
    FileSystemException('Permission denied', path, const OSError('', 13)),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FailedWatchOverrides extends IOOverrides {
  _FailedWatchOverrides(this.deniedPath);
  final String deniedPath;
  @override
  Directory createDirectory(String path) {
    final directory = super.createDirectory(path);
    return FilePaths.same(path, deniedPath)
        ? _FailedWatchDirectory(directory)
        : directory;
  }
}

class _FailedWatchDirectory implements Directory {
  _FailedWatchDirectory(this.delegate);
  final Directory delegate;
  @override
  String get path => delegate.path;
  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => Stream.error(FileSystemException('watch denied', path));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
