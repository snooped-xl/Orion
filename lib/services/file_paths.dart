import 'dart:io';

/// Filename and comparison rules use the host filesystem, rather than assuming
/// that native Windows pickers return forward slashes or matching letter case.
class FilePaths {
  static bool validWindowsComponent(String component) =>
      component.isNotEmpty &&
      !component.endsWith(' ') &&
      !component.endsWith('.') &&
      !RegExp(r'[<>:"\\|?*\x00-\x1f]').hasMatch(component) &&
      !RegExp(
        r'^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$)',
        caseSensitive: false,
      ).hasMatch(component);

  static String basename(String path, {bool? windows}) =>
      ((windows ?? Platform.isWindows) ? path.replaceAll('\\', '/') : path)
          .split('/')
          .last;

  static bool same(String first, String second, {bool? windows}) {
    final onWindows = windows ?? Platform.isWindows;
    String normalize(String path) {
      final normalized = Uri.file(
        path,
        windows: onWindows,
      ).normalizePath().toFilePath(windows: onWindows);
      return onWindows ? normalized.toLowerCase() : normalized;
    }

    return normalize(first) == normalize(second);
  }

  /// Both paths must already be absolute and resolved through the filesystem.
  static bool containsResolvedFile(
    String root,
    String target, {
    bool? windows,
  }) {
    final onWindows = windows ?? Platform.isWindows;
    String normalize(String path) {
      final value = onWindows ? path.replaceAll('\\', '/').toLowerCase() : path;
      return value.replaceFirst(RegExp(r'/+$'), '');
    }

    return normalize(target).startsWith('${normalize(root)}/');
  }
}
