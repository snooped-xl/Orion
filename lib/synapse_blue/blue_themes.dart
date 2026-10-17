import 'dart:convert';

import '../services/synapse_editor_themes.dart';
import 'blue_theme.dart';

abstract final class BlueThemeCodec {
  static String cssName(String key) => key
      .replaceAllMapped(RegExp(r'[A-Z]'), (m) => '-${m[0]!.toLowerCase()}')
      .replaceAll('.', '-');
  static Map<String, Object?> parseCss(String source) {
    final names = {
      for (final key in BluePalette.defaults.keys) cssName(key): key,
    };
    return {
      for (final match in RegExp(
        r'--([a-z0-9-]+)\s*:\s*(#[a-fA-F0-9]{6})\s*;',
      ).allMatches(source))
        if (names.containsKey(match[1]))
          names[match[1]]!:
              0xff000000 | int.parse(match[2]!.substring(1), radix: 16),
    };
  }

  static String encode(Map<String, Object?> preferences) {
    final palette = BluePalette(
      preferences['themeColors'] is Map
          ? Map<String, Object?>.from(preferences['themeColors'] as Map)
          : const {},
    );
    final theme = <String, Object?>{};
    for (final key in BluePalette.defaults.keys) {
      final parts = key.split('.');
      var destination = theme;
      for (final part in parts.take(parts.length - 1)) {
        destination =
            destination.putIfAbsent(part, () => <String, Object?>{})
                as Map<String, Object?>;
      }
      destination[parts.last] =
          '#${(palette.color(key).toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
    }
    theme['uiFontFamily'] = preferences['uiFontFamily'] ?? 'SynapseInter';
    theme['uiFontSizeStep'] = preferences['uiFontSizeStep'] ?? 0;
    theme['editorMonacoThemeId'] =
        preferences['editorThemeId'] ?? 'tomorrow-night-eighties';
    return const JsonEncoder.withIndent(
      '  ',
    ).convert({'format': 'synapse-blue-theme', 'version': 1, 'theme': theme});
  }

  static Map<String, Object?> decode(String source) {
    if (source.length > 256000) {
      throw const FormatException('The theme file is too large.');
    }
    final payload = jsonDecode(source);
    if (payload is! Map) {
      throw const FormatException('Expected a JSON theme object.');
    }
    final raw = payload['blue'] ?? payload['theme'] ?? payload;
    if (raw is! Map) {
      throw const FormatException('Expected a JSON theme object.');
    }
    final flat = <String, Object?>{};
    void visit(Map values, String prefix, int depth) {
      if (depth > 8) return;
      for (final entry in values.entries) {
        if (entry.key is String) {
          final key = prefix.isEmpty
              ? entry.key as String
              : '$prefix.${entry.key}';
          if (entry.value is Map) {
            visit(entry.value as Map, key, depth + 1);
          } else {
            flat[key] = entry.value;
          }
        }
      }
    }

    visit(raw, '', 0);
    final colors = <String, Object?>{};
    for (final key in BluePalette.defaults.keys) {
      final value = flat[key];
      if (value is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
        colors[key] = 0xff000000 | int.parse(value.substring(1), radix: 16);
      }
      if (value is int && value >= 0 && value <= 0xffffffff) {
        colors[key] = value;
      }
    }
    if (colors.isEmpty) {
      throw const FormatException('No supported Blue theme colors were found.');
    }
    return {
      'themeColors': colors,
      if ([
        'SynapseInter',
        'SynapseRubik',
        'RobotoFlex',
      ].contains(flat['uiFontFamily']))
        'uiFontFamily': flat['uiFontFamily'],
      if (flat['uiFontSizeStep'] is num)
        'uiFontSizeStep': (flat['uiFontSizeStep'] as num).toInt().clamp(-3, 3),
      if (synapseEditorThemes.containsKey(flat['editorMonacoThemeId']))
        'editorThemeId': flat['editorMonacoThemeId'],
    };
  }
}
