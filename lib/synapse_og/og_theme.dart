import '../widgets/synapse_theme_surface.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Defaults copied from the pinned Synapse Original ogTheme.ts.
class OgTheme {
  OgTheme(Map<String, Object?> preferences)
    : data = _normalize(preferences['theme']);
  final Map<String, Object?> data;
  static const colors = <String, String>{
    'windowBg': '#232323',
    'panelBg': '#282828',
    'text': '#ffffff',
    'buttonBg': '#272727',
    'buttonHoverBg': '#303030',
    'buttonActiveBg': '#2a2a2a',
    'buttonBorder': '#2d2d2d',
    'buttonText': '#ffffff',
    'tabBg': '#323232',
    'tabActiveBg': '#3c3c3c',
    'tabBorder': '#3a3a3a',
    'tabActiveBorder': '#484848',
    'tabText': '#c0c0c0',
    'editorBg': '#232323',
    'listHoverBg': '#333333',
    'listText': '#c0c0c0',
    'iconColor': '#c0c0c0',
    'logoTextColor': '#ffffff',
    'scriptList.sectionHeaderBg': '#282828',
    'scriptList.sectionHeaderText': '#c0c0c0',
    'scriptList.sectionIcon': '#c0c0c0',
    'scriptList.searchBg': '#323232',
    'scriptList.searchPlaceholder': '#6f6f6e',
    'scriptList.rowText': '#c0c0c0',
    'scriptList.rowHoverBg': '#333333',
    'scriptList.rowMutedText': '#5a5a5a',
  };
  static const cssKeys = <String, String>{
    'window-bg': 'windowBg',
    'panel-bg': 'panelBg',
    'text': 'text',
    'button-bg': 'buttonBg',
    'button-hover-bg': 'buttonHoverBg',
    'button-active-bg': 'buttonActiveBg',
    'button-border': 'buttonBorder',
    'button-text': 'buttonText',
    'tab-bg': 'tabBg',
    'tab-active-bg': 'tabActiveBg',
    'tab-border': 'tabBorder',
    'tab-active-border': 'tabActiveBorder',
    'tab-text': 'tabText',
    'editor-bg': 'editorBg',
    'list-hover-bg': 'listHoverBg',
    'list-text': 'listText',
    'icon-color': 'iconColor',
    'script-section-bg': 'scriptList.sectionHeaderBg',
    'script-section-text': 'scriptList.sectionHeaderText',
    'script-section-icon': 'scriptList.sectionIcon',
    'script-search-bg': 'scriptList.searchBg',
    'script-search-placeholder': 'scriptList.searchPlaceholder',
    'script-row-text': 'scriptList.rowText',
    'script-row-hover': 'scriptList.rowHoverBg',
    'script-row-muted': 'scriptList.rowMutedText',
  };
  String colorsCss() =>
      data['advancedModeCss'] is String &&
          (data['advancedModeCss'] as String).trim().isNotEmpty
      ? data['advancedModeCss'] as String
      : cssKeys.entries
            .map((entry) => '--og-${entry.key}: ${hex(entry.value)};')
            .join('\n');
  Color color(String key) => Color(data[key] as int);
  String hex(String key) =>
      '#${((data[key] as int) & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  Color get window => color('windowBg');
  Color get panel => color('panelBg');
  Color get text => color('text');
  Color get editor => color('editorBg');
  double get opacity => data['overlayOpacity'] as double;
  bool get overlayAbove => data['overlayMode'] == 'top';
  Uint8List? image(String key) {
    final raw = data[key];
    if (raw is! String) return null;
    try {
      return base64Decode(raw.split(',').last);
    } on Object {
      return null;
    }
  }

  Map<String, Object?> update(String key, Object? value) => {
    ...data,
    key: value,
  };
  static Map<String, Object?> _normalize(Object? value) {
    final raw = value is Map ? value : const {};
    final result = <String, Object?>{
      for (final e in colors.entries)
        e.key: 0xff000000 | int.parse(e.value.substring(1), radix: 16),
      'overlayOpacity': .35,
      'overlayMode': 'behind',
      'logoMode': 'image',
      'logoPreset': 'synapseOriginal',
      'logoTextFontId': 'inter',
      'logoText': 'Synapse',
      'logoTextSizePx': 14.0,
      'logoTextWeight': 600.0,
      'logoTextLetterSpacing': 0.0,
      'logoDataUrl': null,
      'overlayDataUrl': null,
      'advancedModeCss': '',
    };
    final expanded = <String, Object?>{
      for (final e in raw.entries)
        if (e.key is String) e.key: e.value,
    };
    if (raw['scriptList'] is Map) {
      for (final e in (raw['scriptList'] as Map).entries) {
        expanded['scriptList.${e.key}'] = e.value;
      }
    }
    for (final key in colors.keys) {
      final v = expanded[key];
      if (v is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)) {
        result[key] = 0xff000000 | int.parse(v.substring(1), radix: 16);
      } else if (v is int && v >= 0 && v <= 0xffffffff) {
        result[key] = v;
      }
    }
    for (final key in ['logoDataUrl', 'overlayDataUrl']) {
      final v = raw[key];
      if (v is String &&
          v.length <= 6 * 1024 * 1024 &&
          RegExp(r'^data:image/(png|jpeg|webp|gif);base64,').hasMatch(v)) {
        result[key] = v;
      }
    }
    if (['top', 'behind'].contains(raw['overlayMode'])) {
      result['overlayMode'] = raw['overlayMode'];
    }
    if (['image', 'text'].contains(raw['logoMode'])) {
      result['logoMode'] = raw['logoMode'];
    }
    for (final key in [
      'logoText',
      'advancedModeCss',
      'logoPreset',
      'logoTextFontId',
    ]) {
      final v = raw[key];
      if (v is String) {
        result[key] = v.substring(
          0,
          v.length.clamp(0, key == 'logoText' ? 100 : 32000),
        );
      }
    }
    for (final entry in {
      'overlayOpacity': (0.0, 1.0),
      'logoTextSizePx': (8.0, 32.0),
      'logoTextWeight': (300.0, 900.0),
      'logoTextLetterSpacing': (-2.0, 8.0),
    }.entries) {
      final v = raw[entry.key];
      if (v is num && v.isFinite) {
        result[entry.key] = v.toDouble().clamp(entry.value.$1, entry.value.$2);
      }
    }
    return Map.unmodifiable(result);
  }

  static Map<String, Object?> decode(String json) {
    if (json.length > 12 * 1024 * 1024) {
      throw const FormatException('Theme is too large.');
    }
    final value = jsonDecode(json);
    if (value is! Map) {
      throw const FormatException('Expected a JSON theme object.');
    }
    return _normalize(value);
  }

  String encode() {
    final value = <String, Object?>{
      ...data,
      for (final key in colors.keys) key: hex(key),
    };
    final scriptList = <String, Object?>{};
    for (final key in colors.keys.where((k) => k.startsWith('scriptList.'))) {
      scriptList[key.split('.').last] = value.remove(key);
    }
    value['scriptList'] = scriptList;
    return const JsonEncoder.withIndent('  ').convert(value);
  }
}

TextStyle ogText(
  double size, {
  Color color = Colors.white,
  FontWeight weight = FontWeight.w400,
  double? height,
}) => TextStyle(
  fontFamily: 'SynapseInter',
  fontSize: size,
  color: color,
  fontWeight: weight,
  letterSpacing: 0,
  height: height,
);

class OgLogo extends StatelessWidget {
  const OgLogo({super.key, required this.theme});
  final OgTheme theme;
  @override
  Widget build(BuildContext context) {
    if (theme.data['logoMode'] == 'text') {
      return Text(
        theme.data['logoText'] as String,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style:
            ogText(
              theme.data['logoTextSizePx'] as double,
              color: theme.color('logoTextColor'),
              weight:
                  FontWeight.values[((theme.data['logoTextWeight'] as double) /
                              100)
                          .round()
                          .clamp(1, 9) -
                      1],
            ).copyWith(
              fontFamily: SynapseThemeElementStyleScope.fontFamilyOf(context),
              letterSpacing: theme.data['logoTextLetterSpacing'] as double,
            ),
      );
    }
    final bytes = theme.image('logoDataUrl');
    return bytes == null
        ? Image.asset(
            'assets/synapse_og/synapse-logo.png',
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
          )
        : Image.memory(
            bytes,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (_, _, _) => Image.asset(
              'assets/synapse_og/synapse-logo.png',
              fit: BoxFit.contain,
            ),
          );
  }
}

class OgButton extends StatelessWidget {
  const OgButton(
    this.label, {
    super.key,
    required this.theme,
    this.onPressed,
    this.width,
    this.height = 33,
    this.fontSize = 13,
    this.selected = false,
    this.border,
    this.background,
    this.textColor,
    this.labelChild,
  });
  final String label;
  final OgTheme theme;
  final VoidCallback? onPressed;
  final double? width;
  final double height, fontSize;
  final bool selected;
  final Color? border, background, textColor;
  final Widget? labelChild;
  @override
  Widget build(BuildContext context) {
    final element = SynapseThemeElementStyleScope.maybeOf(context);
    final hasImage =
        element?.image?.isValid == true && element!.image!.opacity > 0;
    final theme = OgTheme({
      'theme': {
        ...this.theme.data,
        if (element?.fill != null || hasImage)
          'buttonBg': hasImage ? 0x00000000 : element!.fill,
        if (element?.fill != null || hasImage)
          'buttonHoverBg': hasImage ? 0x00000000 : element!.fill,
        if (element?.fill != null || hasImage)
          'buttonActiveBg': hasImage ? 0x00000000 : element!.fill,
        if (element?.foreground != null) 'buttonText': element!.foreground,
        if (element?.border != null) 'buttonBorder': element!.border,
      },
    });
    final border = element?.border == null
        ? this.border
        : Color(element!.border!);
    final background = hasImage
        ? Colors.transparent
        : element?.fill == null
        ? this.background
        : Color(element!.fill!);
    final textColor = element?.foreground == null
        ? this.textColor
        : Color(element!.foreground!);
    return SizedBox(
      width: width,
      height: height,
      child: TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          padding: WidgetStateProperty.all(EdgeInsets.zero),
          minimumSize: WidgetStateProperty.all(Size.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(element?.radius ?? 0),
            ),
          ),
          side: WidgetStateProperty.all(
            BorderSide(
              color:
                  border ??
                  theme.color(selected ? 'tabActiveBorder' : 'buttonBorder'),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.pressed)
                ? theme.color('buttonActiveBg')
                : s.contains(WidgetState.hovered)
                ? theme.color('buttonHoverBg')
                : background ?? theme.color(selected ? 'tabBg' : 'buttonBg'),
          ),
          foregroundColor: WidgetStateProperty.all(
            textColor ?? theme.color('buttonText'),
          ),
          textStyle: WidgetStateProperty.all(
            ogText(fontSize).copyWith(
              fontFamily: SynapseThemeElementStyleScope.fontFamilyOf(context),
            ),
          ),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
        ),
        child: Opacity(
          opacity: onPressed == null ? .5 : 1,
          child: labelChild ?? Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// Owns its editor through the route's exit animation, including theme changes.
class OgInputDialog extends StatefulWidget {
  const OgInputDialog({
    super.key,
    required this.title,
    required this.theme,
    this.initialText = '',
    this.confirmLabel = 'OK',
    this.validator,
  });
  final String title, initialText, confirmLabel;
  final OgTheme theme;
  final String? Function(String)? validator;
  @override
  State<OgInputDialog> createState() => _OgInputDialogState();
}

class _OgInputDialogState extends State<OgInputDialog> {
  late final _input = TextEditingController(text: widget.initialText);
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    final error = widget.validator?.call(_input.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, _input.text);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 300,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: ogText(14)),
            const SizedBox(height: 10),
            TextField(
              controller: _input,
              autofocus: true,
              style: ogText(13).copyWith(
                fontFamily: SynapseThemeElementStyleScope.fontFamilyOf(context),
              ),
              decoration: InputDecoration(isDense: true, errorText: _error),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OgButton(
                  widget.confirmLabel,
                  theme: widget.theme,
                  width: 75,
                  onPressed: _submit,
                ),
                const SizedBox(width: 8),
                OgButton(
                  'Cancel',
                  theme: widget.theme,
                  width: 75,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
