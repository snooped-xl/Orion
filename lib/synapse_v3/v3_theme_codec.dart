import 'dart:convert';
import 'synapse_v3_preferences.dart';
import 'synapse_v3_theme.dart';

/// Reads the source's JSON theme format, and the first Orion V3 JSON format.
/// Only supported frontend tokens are applied; no executable data is read.
abstract final class V3ThemeCodec {
  static const _groups = {
    'shell',
    'topBar',
    'editor',
    'scriptList',
    'actionBar',
    'settingsChrome',
    'scriptHub',
    'accent',
    'icons',
    'branding',
  };
  static String encode(SynapsePreferences prefs) {
    final theme = <String, Object?>{};
    void put(String path, Object? value) {
      final parts = path.split('.');
      var map = theme;
      for (final part in parts.take(parts.length - 1)) {
        map =
            map.putIfAbsent(part, () => <String, Object?>{})
                as Map<String, Object?>;
      }
      map[parts.last] = value;
    }

    final colors = {
      ...V3ThemePresets.colors[prefs.themePreset]!,
      ...prefs.themeColors,
    };
    for (final entry in colors.entries) {
      if (!_groups.contains(entry.key.split('.').first)) continue;
      final argb = entry.value, a = (argb >> 24) & 255;
      final css = a == 255
          ? '#${(argb & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}'
          : 'rgba(${(argb >> 16) & 255}, ${(argb >> 8) & 255}, ${argb & 255}, ${(a / 255).toStringAsFixed(4)})';
      put(entry.key, css);
    }
    put('shell.cornerRadiusPx', prefs.cornerRadius);
    put('simple.presetId', prefs.themePreset);
    put(
      'typography.uiFontFamily',
      prefs.uiFontFamily == 'SynapseRubik'
          ? 'Rubik, sans-serif'
          : 'Inter, sans-serif',
    );
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'synapse-v3-theme',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'theme': theme,
    });
  }

  static SynapsePreferences decode(String source, SynapsePreferences current) {
    if (source.length > 256000) {
      throw const FormatException('The theme file is too large.');
    }
    final payload = jsonDecode(source);
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON theme object.');
    }
    if (payload['format'] == 'orion-synapse-v3-theme' &&
        payload['version'] == 1) {
      return SynapsePreferences.fromJson({
        ...current.toJson(),
        for (final key in [
          'themePreset',
          'themeColors',
          'uiFontFamily',
          'cornerRadius',
        ])
          if (payload.containsKey(key)) key: payload[key],
      });
    }
    if (payload.containsKey('format') &&
        payload['format'] != 'synapse-v3-theme') {
      throw const FormatException('Unsupported theme format.');
    }
    if (payload['format'] == 'synapse-v3-theme' && payload['version'] != 1) {
      throw const FormatException('Unsupported theme version.');
    }
    final raw = payload['theme'] ?? payload;
    if (raw is! Map) {
      throw const FormatException('Expected a JSON theme object.');
    }
    final flat = <String, Object?>{};
    void visit(Map map, String prefix, int depth) {
      if (depth > 8) return;
      for (final entry in map.entries) {
        if (entry.key is! String) continue;
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

    visit(raw, '', 0);
    final preset = SynapsePreferences.presets.contains(flat['simple.presetId'])
        ? flat['simple.presetId'] as String
        : current.themePreset;
    final colors = <String, int>{...V3ThemePresets.colors[preset]!};
    var changed = 0;
    for (final entry in flat.entries) {
      if (!_groups.contains(entry.key.split('.').first) ||
          !V3ThemePresets.colors['framework']!.containsKey(entry.key)) {
        continue;
      }
      final color = _parseColor(entry.value);
      if (color != null) {
        colors[entry.key] = color;
        changed++;
      }
    }
    if (changed == 0) {
      throw const FormatException(
        'This file contains no supported V3 theme colors.',
      );
    }
    final font = flat['typography.uiFontFamily'];
    return SynapsePreferences.fromJson({
      ...current.toJson(),
      'themePreset': preset,
      'themeColors': colors,
      if (font is String)
        'uiFontFamily': font.toLowerCase().contains('rubik')
            ? 'SynapseRubik'
            : 'SynapseInter',
      if (flat['shell.cornerRadiusPx'] is num)
        'cornerRadius': flat['shell.cornerRadiusPx'],
    });
  }

  static int? _parseColor(Object? value) {
    if (value is int && value >= 0 && value <= 0xffffffff) return value;
    if (value is! String) return null;
    final hex = RegExp(
      r'^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$',
    ).firstMatch(value.trim());
    if (hex != null) {
      return (hex.group(2) == null
                  ? 0xff
                  : int.parse(hex.group(2)!, radix: 16)) <<
              24 |
          int.parse(hex.group(1)!, radix: 16);
    }
    final rgba = RegExp(
      r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)$',
    ).firstMatch(value.trim());
    if (rgba == null) return null;
    final channels = [for (var i = 1; i <= 3; i++) int.parse(rgba.group(i)!)];
    final alpha = rgba.group(4) == null ? 1.0 : double.tryParse(rgba.group(4)!);
    if (channels.any((v) => v > 255) ||
        alpha == null ||
        !alpha.isFinite ||
        alpha < 0 ||
        alpha > 1) {
      return null;
    }
    return (alpha * 255).round() << 24 |
        channels[0] << 16 |
        channels[1] << 8 |
        channels[2];
  }
}
