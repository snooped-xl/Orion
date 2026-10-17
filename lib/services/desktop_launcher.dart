import 'dart:io';

/// Launches desktop handlers directly, without passing paths or URLs to a shell.
class DesktopLaunchCommand {
  const DesktopLaunchCommand(this.executable, this.arguments, this.detached);
  final String executable;
  final List<String> arguments;
  final bool detached;
}

class DesktopLauncher {
  static DesktopLaunchCommand commandForUrl(Uri uri, {String? platform}) {
    if (!{'https', 'http'}.contains(uri.scheme) || uri.host.isEmpty) {
      throw const FormatException('The source link is not available.');
    }
    return _command(uri.toString(), platform: platform);
  }

  static DesktopLaunchCommand commandForDirectory(
    String path, {
    String? platform,
  }) => _command(path, platform: platform);

  static DesktopLaunchCommand commandForReveal(
    String path, {
    String? platform,
  }) {
    final system = platform ?? Platform.operatingSystem;
    if (system == 'windows') {
      return DesktopLaunchCommand('explorer.exe', ['/select,', path], true);
    }
    if (system == 'macos') {
      return DesktopLaunchCommand('open', ['-R', path], false);
    }
    return _command(File(path).parent.path, platform: system);
  }

  static DesktopLaunchCommand _command(String target, {String? platform}) {
    switch (platform ?? Platform.operatingSystem) {
      case 'windows':
        // Explorer dispatches URLs to the user's default browser and opens
        // directories in an existing Explorer process. Its exit code is not a
        // reliable success signal, so do not wait for that process to finish.
        return DesktopLaunchCommand('explorer.exe', [target], true);
      case 'macos':
        return DesktopLaunchCommand('open', [target], false);
      case 'linux':
        return DesktopLaunchCommand('xdg-open', [target], false);
      default:
        throw UnsupportedError('No desktop launcher is available.');
    }
  }

  static Future<void> openUrl(Uri uri) => _run(commandForUrl(uri));
  static Future<void> openDirectory(Directory directory) =>
      _run(commandForDirectory(directory.absolute.path));
  static Future<void> revealFile(File file) =>
      _run(commandForReveal(file.absolute.path));

  static Future<void> _run(DesktopLaunchCommand command) async {
    if (command.detached) {
      await Process.start(
        command.executable,
        command.arguments,
        mode: ProcessStartMode.detached,
      );
      return;
    }
    final result = await Process.run(
      command.executable,
      command.arguments,
    ).timeout(const Duration(seconds: 8));
    if (result.exitCode != 0) {
      throw const FileSystemException('Could not open the desktop handler.');
    }
  }
}
