import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/desktop_launcher.dart';

void main() {
  test('Windows URLs use direct argv and preserve query metacharacters', () {
    final url = Uri.parse('https://example.com/script?a=1&b=hello%20world');
    final command = DesktopLauncher.commandForUrl(url, platform: 'windows');
    expect(command.executable, 'explorer.exe');
    expect(command.arguments, [url.toString()]);
    expect(command.detached, isTrue);
  });

  test(
    'Windows paths and file selection never use xdg-open or a command shell',
    () {
      const path = r'D:\My Documents\orion\scripts\a & b.lua';
      final open = DesktopLauncher.commandForDirectory(
        path,
        platform: 'windows',
      );
      final reveal = DesktopLauncher.commandForReveal(
        path,
        platform: 'windows',
      );
      expect(open.executable, 'explorer.exe');
      expect(open.arguments, [path]);
      expect(reveal.arguments, ['/select,', path]);
      expect(reveal.detached, isTrue);
    },
  );

  test('Linux and macOS retain their native desktop handlers', () {
    expect(
      DesktopLauncher.commandForDirectory(
        '/home/a/orion',
        platform: 'linux',
      ).executable,
      'xdg-open',
    );
    expect(
      DesktopLauncher.commandForDirectory(
        '/Users/a/orion',
        platform: 'macos',
      ).executable,
      'open',
    );
    expect(
      DesktopLauncher.commandForReveal(
        '/Users/a/test.lua',
        platform: 'macos',
      ).arguments,
      ['-R', '/Users/a/test.lua'],
    );
  });

  test('external URL launch rejects local and executable protocols', () {
    for (final value in [
      'file:///tmp/a.lua',
      'javascript:alert(1)',
      'https:',
      'ftp://example.com/a',
    ]) {
      expect(
        () => DesktopLauncher.commandForUrl(Uri.parse(value)),
        throwsFormatException,
      );
    }
  });
}
