import 'package:flutter/material.dart';

/// Manual V3 preferences. Automation and execution-engine configuration are
/// deliberately absent; this state is safe to share with the local editor.
@immutable
class SynapsePreferences {
  const SynapsePreferences({
    this.alwaysOnTop = false,
    this.resizable = false,
    this.showScriptList = true,
    this.minimap = false,
    this.errorLogging = false,
    this.compactButtons = false,
    this.compactTabs = false,
    this.consoleTimestamp = true,
    this.defaultTabContent = '',
    this.themePreset = 'framework',
    this.uiFontFamily = 'SynapseInter',
    this.consoleHeight = 160,
    this.consoleFontSize = 11,
    this.cornerRadius = 7,
    this.themeColors = const {},
    this.gistUrls = const [],
    this.bookmarkedDocumentIds = const [],
    this.gistDocumentUrls = const {},
  });

  final bool alwaysOnTop, resizable, showScriptList, minimap, errorLogging;
  final bool compactButtons, compactTabs, consoleTimestamp;
  final String defaultTabContent, themePreset, uiFontFamily;
  final double consoleHeight, consoleFontSize, cornerRadius;
  final Map<String, int> themeColors;
  final List<String> gistUrls, bookmarkedDocumentIds;
  final Map<String, String> gistDocumentUrls;

  Color get themeBackground => color(
    'shell.pageBg',
    fallback: themePreset == 'legacyFramework'
        ? const Color(0xff151515)
        : Colors.black,
  );
  Color get themeAccent =>
      color('accent.primary', fallback: const Color(0xff225a7a));
  Color get themeText => color('topBar.text', fallback: Colors.white);
  Color get themeMuted =>
      color('topBar.mutedText', fallback: const Color(0xff8d8d8d));
  Color color(String key, {Color fallback = Colors.white}) =>
      themeColors[key] == null ? fallback : Color(themeColors[key]!);

  SynapsePreferences copyWith({
    bool? alwaysOnTop,
    bool? resizable,
    bool? showScriptList,
    bool? minimap,
    bool? errorLogging,
    bool? compactButtons,
    bool? compactTabs,
    bool? consoleTimestamp,
    String? defaultTabContent,
    String? themePreset,
    String? uiFontFamily,
    double? consoleHeight,
    double? consoleFontSize,
    double? cornerRadius,
    Color? themeBackground,
    Color? themeAccent,
    Map<String, int>? themeColors,
    List<String>? gistUrls,
    List<String>? bookmarkedDocumentIds,
    Map<String, String>? gistDocumentUrls,
  }) => SynapsePreferences.fromJson({
    ...toJson(),
    'alwaysOnTop': ?alwaysOnTop,
    'resizable': ?resizable,
    'showScriptList': ?showScriptList,
    'minimap': ?minimap,
    'errorLogging': ?errorLogging,
    'compactButtons': ?compactButtons,
    'compactTabs': ?compactTabs,
    'consoleTimestamp': ?consoleTimestamp,
    'defaultTabContent': ?defaultTabContent,
    'themePreset': ?themePreset,
    'uiFontFamily': ?uiFontFamily,
    'consoleHeight': ?consoleHeight,
    'consoleFontSize': ?consoleFontSize,
    'cornerRadius': ?cornerRadius,
    'gistUrls': ?gistUrls,
    'bookmarkedDocumentIds': ?bookmarkedDocumentIds,
    'gistDocumentUrls': ?gistDocumentUrls,
    'themeColors': {
      ...this.themeColors,
      ...?themeColors,
      if (themeBackground != null) 'shell.pageBg': themeBackground.toARGB32(),
      if (themeBackground != null)
        'shell.contentBg': themeBackground.toARGB32(),
      if (themeAccent != null) 'accent.primary': themeAccent.toARGB32(),
    },
  });

  Map<String, Object?> toJson() => {
    'alwaysOnTop': alwaysOnTop,
    'resizable': resizable,
    'showScriptList': showScriptList,
    'minimap': minimap,
    'errorLogging': errorLogging,
    'compactButtons': compactButtons,
    'compactTabs': compactTabs,
    'consoleTimestamp': consoleTimestamp,
    'defaultTabContent': defaultTabContent,
    'themePreset': themePreset,
    'uiFontFamily': uiFontFamily,
    'consoleHeight': consoleHeight,
    'consoleFontSize': consoleFontSize,
    'cornerRadius': cornerRadius,
    'themeColors': themeColors,
    'gistUrls': gistUrls,
    'bookmarkedDocumentIds': bookmarkedDocumentIds,
    'gistDocumentUrls': gistDocumentUrls,
  };

  static const presets = [
    'framework',
    'legacyFramework',
    'midnight',
    'graphite',
    'ocean',
    'ember',
    'highContrast',
    'novo',
  ];
  static SynapsePreferences fromJson(Object? value) {
    final data = value is Map ? value : const <String, Object?>{};
    bool readBool(String key, bool fallback) =>
        data[key] is bool ? data[key] as bool : fallback;
    double number(String key, double fallback, double min, double max) {
      final raw = data[key];
      return raw is num && raw.isFinite
          ? raw.toDouble().clamp(min, max)
          : fallback;
    }

    final rawColors = data['themeColors'];
    final colors = <String, int>{};
    if (rawColors is Map) {
      for (final entry in rawColors.entries.take(160)) {
        if (entry.key is String &&
            (entry.key as String).length < 100 &&
            RegExp(
              r'^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*)+$',
            ).hasMatch(entry.key) &&
            entry.value is int &&
            entry.value >= 0 &&
            entry.value <= 0xffffffff) {
          colors[entry.key] = entry.value;
        }
      }
    }
    final content = data['defaultTabContent'];
    List<String> strings(String key) => data[key] is List
        ? (data[key] as List)
              .whereType<String>()
              .where(
                (s) =>
                    s.isNotEmpty &&
                    s.length < 2048 &&
                    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(s),
              )
              .toSet()
              .take(200)
              .toList()
        : const [];
    final gists = strings('gistUrls').where((url) {
      final uri = Uri.tryParse(url);
      return uri != null &&
          ['http', 'https'].contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty;
    });
    final rawGistDocuments = data['gistDocumentUrls'];
    final gistDocuments = <String, String>{};
    if (rawGistDocuments is Map) {
      for (final entry in rawGistDocuments.entries.take(200)) {
        if (entry.key is! String ||
            entry.key.isEmpty ||
            entry.key.length > 256 ||
            entry.value is! String ||
            entry.value.length > 2048 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(entry.value)) {
          continue;
        }
        final uri = Uri.tryParse(entry.value);
        if (uri != null &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty) {
          gistDocuments[entry.key] = entry.value;
        }
      }
    }
    return SynapsePreferences(
      gistDocumentUrls: Map.unmodifiable(gistDocuments),
      alwaysOnTop: readBool('alwaysOnTop', false),
      resizable: readBool('resizable', false),
      showScriptList: readBool('showScriptList', true),
      minimap: readBool('minimap', false),
      errorLogging: readBool('errorLogging', false),
      compactButtons: readBool('compactButtons', false),
      compactTabs: readBool('compactTabs', false),
      consoleTimestamp: readBool('consoleTimestamp', true),
      defaultTabContent: content is String
          ? content.substring(0, content.length.clamp(0, 100000))
          : '',
      themePreset: presets.contains(data['themePreset'])
          ? data['themePreset'] as String
          : 'framework',
      uiFontFamily:
          ['SynapseInter', 'SynapseRubik'].contains(data['uiFontFamily'])
          ? data['uiFontFamily'] as String
          : 'SynapseInter',
      consoleHeight: number('consoleHeight', 160, 64, 360),
      consoleFontSize: number('consoleFontSize', 11, 9, 18),
      cornerRadius: number('cornerRadius', 7, 0, 16),
      themeColors: Map.unmodifiable(colors),
      gistUrls: List.unmodifiable(gists),
      bookmarkedDocumentIds: List.unmodifiable(
        strings('bookmarkedDocumentIds'),
      ),
    );
  }
}
