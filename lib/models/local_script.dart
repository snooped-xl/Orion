enum ScriptColorCode { none, white, blue, green, red, special }

extension ScriptColorCodeLabel on ScriptColorCode {
  String get label => switch (this) {
    ScriptColorCode.none => 'None',
    ScriptColorCode.white => 'White',
    ScriptColorCode.blue => 'Blue',
    ScriptColorCode.green => 'Green',
    ScriptColorCode.red => 'Red',
    ScriptColorCode.special => 'Special',
  };
}

/// A filesystem item in Orion's dedicated script library.
/// [relativePath] uses '/' separators; [path] is its absolute filesystem path.
class LocalScriptEntry {
  const LocalScriptEntry({
    required this.relativePath,
    required this.name,
    required this.path,
    required this.isDirectory,
    this.code = ScriptColorCode.none,
  });

  final String relativePath;
  final String name;
  final String path;
  final bool isDirectory;
  final ScriptColorCode code;

  @override
  bool operator ==(Object other) =>
      other is LocalScriptEntry &&
      relativePath == other.relativePath &&
      name == other.name &&
      path == other.path &&
      isDirectory == other.isDirectory &&
      code == other.code;

  @override
  int get hashCode => Object.hash(relativePath, name, path, isDirectory, code);
}
