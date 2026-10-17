import '../models/interface_preset.dart';
import '../models/synapse_studio_theme.dart';
import '../state/orion_controller.dart';

class SavedStudioTheme {
  const SavedStudioTheme({
    required this.id,
    required this.name,
    required this.document,
  });
  final String id, name, document;
  SynapseStudioTheme get theme => SynapseStudioTheme.decode(document);
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'document': document,
  };
}

/// Named documents are stored as strings so nested image data survives the
/// workspace's deliberately shallow, JSON-safe interface preference copier.
class ThemeStudioLibrary {
  ThemeStudioLibrary(this.controller, this.preset);
  final OrionController controller;
  final InterfacePreset preset;
  static const preferenceKey = 'themeStudioSavedThemes';
  static const maximumThemes = 24;
  static const maximumCharacters = 64 * 1024 * 1024;
  static var _sequence = 0;

  List<SavedStudioTheme> get themes {
    final raw = controller.getInterfacePreferences(preset)[preferenceKey];
    if (raw is! List) return const [];
    return List.unmodifiable([
      for (final item in raw.take(maximumThemes))
        if (item is Map &&
            item['id'] is String &&
            item['name'] is String &&
            item['document'] is String &&
            (item['document'] as String).length <= maximumCharacters)
          SavedStudioTheme(
            id: item['id'] as String,
            name: item['name'] as String,
            document: item['document'] as String,
          ),
    ]);
  }

  static String cleanName(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) throw const FormatException('Enter a theme name.');
    if (cleaned.length > 60) {
      throw const FormatException('Use at most 60 characters.');
    }
    return cleaned;
  }

  Future<SavedStudioTheme> save(
    String name,
    SynapseStudioTheme document, {
    String? replaceId,
  }) async {
    final label = cleanName(name), previous = themes;
    _uniqueName(label, previous, exceptId: replaceId);
    if (replaceId == null && previous.length >= maximumThemes) {
      throw const FormatException(
        'Your saved themes are full. Delete a theme to make room.',
      );
    }
    if (replaceId != null && !previous.any((item) => item.id == replaceId)) {
      throw const FormatException('This saved theme no longer exists.');
    }
    final saved = SavedStudioTheme(
      id:
          replaceId ??
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_sequence++}',
      name: label,
      document: document.copyWith(name: label).encode(),
    );
    final next = [
      for (final item in previous)
        if (item.id != replaceId) item,
      saved,
    ];
    await _write(next);
    return saved;
  }

  Future<SavedStudioTheme> rename(String id, String name) async {
    final item = themes.where((item) => item.id == id).firstOrNull;
    if (item == null) {
      throw const FormatException('This saved theme no longer exists.');
    }
    return save(name, item.theme, replaceId: id);
  }

  Future<void> delete(String id) => _write([
    for (final item in themes)
      if (item.id != id) item,
  ]);

  void _uniqueName(
    String name,
    List<SavedStudioTheme> entries, {
    String? exceptId,
  }) {
    if (entries.any(
      (entry) =>
          entry.id != exceptId &&
          entry.name.toLowerCase() == name.toLowerCase(),
    )) {
      throw const FormatException('A saved theme already uses this name.');
    }
  }

  Future<void> _write(List<SavedStudioTheme> next) async {
    if (next.fold<int>(0, (size, item) => size + item.document.length) >
        maximumCharacters) {
      throw const FormatException(
        'Saved theme images exceed the 64 MB library limit. Remove a theme or use smaller images.',
      );
    }
    final previous = controller.getInterfacePreferences(preset)[preferenceKey];
    try {
      controller.setInterfacePreference(preset, preferenceKey, [
        for (final item in next) item.toJson(),
      ]);
      await controller.flushPersistence();
      if (controller.persistenceError != null) {
        throw FormatException(controller.persistenceError!);
      }
    } on Object {
      controller.setInterfacePreference(preset, preferenceKey, previous);
      rethrow;
    }
  }
}
