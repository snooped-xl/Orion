import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/file_paths.dart';

void main() {
  test('Windows filename labels handle native and mixed path separators', () {
    expect(
      FilePaths.basename(
        r'C:\Users\player\orion\scripts\test.lua',
        windows: true,
      ),
      'test.lua',
    );
    expect(
      FilePaths.basename(
        r'C:\Users\player/orion/scripts/test.lua',
        windows: true,
      ),
      'test.lua',
    );
    expect(
      FilePaths.basename('/home/player/a\\b.lua', windows: false),
      r'a\b.lua',
    );
  });

  test(
    'Windows script identity ignores case, slash style and dot segments',
    () {
      expect(
        FilePaths.same(
          r'C:\Users\Player\orion\scripts\TEST.lua',
          r'c:/users/player/orion/scripts/test.lua',
          windows: true,
        ),
        isTrue,
      );
      expect(
        FilePaths.same(
          r'C:\orion\scripts\a\..\test.lua',
          r'C:\orion\scripts\test.lua',
          windows: true,
        ),
        isTrue,
      );
      expect(
        FilePaths.same(
          r'\\server\Share\a.lua',
          r'\\SERVER\share\A.lua',
          windows: true,
        ),
        isTrue,
      );
      expect(
        FilePaths.same(
          r'C:\orion\scripts\test.lua',
          r'D:\orion\scripts\test.lua',
          windows: true,
        ),
        isFalse,
      );
    },
  );

  test('Linux script identity retains case sensitivity', () {
    expect(
      FilePaths.same('/home/a/Test.lua', '/home/a/test.lua', windows: false),
      isFalse,
    );
    expect(
      FilePaths.same(
        '/home/a/folder/../test.lua',
        '/home/a/test.lua',
        windows: false,
      ),
      isTrue,
    );
  });

  test(
    'resolved asset confinement respects Windows case and directory boundary',
    () {
      expect(
        FilePaths.containsResolvedFile(
          r'C:\Orion\data\monaco',
          r'c:\orion\data\monaco\vs\loader.js',
          windows: true,
        ),
        isTrue,
      );
      expect(
        FilePaths.containsResolvedFile(
          r'C:\Orion\data\monaco',
          r'C:\Orion\data\monaco-other\secret.js',
          windows: true,
        ),
        isFalse,
      );
      expect(
        FilePaths.containsResolvedFile(
          r'C:\Orion\data\monaco',
          r'D:\Orion\data\monaco\secret.js',
          windows: true,
        ),
        isFalse,
      );
      expect(
        FilePaths.containsResolvedFile(
          '/tmp/editor',
          '/tmp/editor-other/private',
          windows: false,
        ),
        isFalse,
      );
      expect(
        FilePaths.containsResolvedFile(
          '/tmp/Editor',
          '/tmp/editor/a.js',
          windows: false,
        ),
        isFalse,
      );
      expect(
        FilePaths.containsResolvedFile(
          '/tmp/editor\\other',
          '/tmp/editor/other/a.js',
          windows: false,
        ),
        isFalse,
      );
    },
  );

  test(
    'Windows filenames reject device aliases, ADS streams and silent trimming',
    () {
      for (final component in [
        'CON.lua',
        'aux.txt',
        'COM1.lua',
        'LPT².lua',
        'folder.',
        'folder ',
        'file.lua:payload',
        'a?b.lua',
        'a"b.lua',
      ]) {
        expect(
          FilePaths.validWindowsComponent(component),
          isFalse,
          reason: component,
        );
      }
      for (final component in [
        'connection.lua',
        'com10.lua',
        'Orion Bridge.lua',
        'my.script.luau',
        'résumé.txt',
      ]) {
        expect(
          FilePaths.validWindowsComponent(component),
          isTrue,
          reason: component,
        );
      }
    },
  );
}
