import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The same lexical categories as assets/editor/luau-language.js. This scanner
/// retains offsets and every character, including incomplete code and IME text.
class LuauToken {
  const LuauToken(this.start, this.end, this.kind);
  final int start, end;
  final String kind;
}

abstract final class LuauSyntax {
  static const keywords = {
    'and',
    'break',
    'continue',
    'do',
    'else',
    'elseif',
    'end',
    'export',
    'false',
    'for',
    'function',
    'if',
    'in',
    'local',
    'nil',
    'not',
    'or',
    'repeat',
    'return',
    'then',
    'true',
    'type',
    'until',
    'while',
  };
  static const types = {
    'any',
    'boolean',
    'buffer',
    'never',
    'nil',
    'number',
    'string',
    'thread',
    'unknown',
    'vector',
  };
  static final _identifier = RegExp(r'[A-Za-z_]\w*');
  static final _number = RegExp(
    r'(?:0[xX][\da-fA-F_]+(?:\.[\da-fA-F_]*)?(?:[pP][+-]?[\d_]+)?|0[bB][01_]+|(?:\d[\d_]*(?:\.(?!\.)[\d_]*)?|\.\d[\d_]*)(?:[eE][+-]?[\d_]+)?)',
  );
  static final _longOpen = RegExp(r'\[(=*)\[');
  static const _operators = '+-*/%^#=<>~?:|&';

  static List<LuauToken> tokenize(String source) {
    final tokens = <LuauToken>[];
    var offset = 0;
    void add(int end, String kind) {
      if (end <= offset) return;
      if (tokens.isNotEmpty && tokens.last.kind == kind) {
        final previous = tokens.removeLast();
        tokens.add(LuauToken(previous.start, end, kind));
      } else {
        tokens.add(LuauToken(offset, end, kind));
      }
      offset = end;
    }

    int longEnd(int start) {
      final opening = _longOpen.matchAsPrefix(source, start);
      if (opening == null) return -1;
      final close = ']${opening.group(1)}]';
      final end = source.indexOf(close, opening.end);
      return end < 0 ? source.length : end + close.length;
    }

    void quoted(String quote) {
      add(offset + 1, 'string');
      var start = offset;
      while (offset < source.length) {
        final character = source[offset];
        if (character == r'\') {
          if (start < offset) tokens.add(LuauToken(start, offset, 'string'));
          final end = (offset + 2).clamp(0, source.length);
          tokens.add(LuauToken(offset, end, 'escape'));
          offset = end;
          start = offset;
        } else if (character == quote) {
          offset++;
          if (start < offset) tokens.add(LuauToken(start, offset, 'string'));
          return;
        } else if (quote == '`' && character == '{') {
          if (start < offset) tokens.add(LuauToken(start, offset, 'string'));
          final end = source.indexOf('}', offset + 1);
          final interpolationEnd = end < 0 ? source.length : end + 1;
          tokens.add(LuauToken(offset, interpolationEnd, 'interpolation'));
          offset = interpolationEnd;
          start = offset;
        } else {
          offset++;
        }
      }
      if (start < offset) tokens.add(LuauToken(start, offset, 'string'));
    }

    while (offset < source.length) {
      if (source.startsWith('--', offset)) {
        final end = longEnd(offset + 2);
        if (end >= 0) {
          add(end, 'comment');
        } else {
          final newline = source.indexOf('\n', offset);
          add(newline < 0 ? source.length : newline, 'comment');
        }
        continue;
      }
      final long = longEnd(offset);
      if (long >= 0) {
        add(long, 'string');
        continue;
      }
      final character = source[offset];
      if (character == '"' || character == "'" || character == '`') {
        quoted(character);
        continue;
      }
      final number = _number.matchAsPrefix(source, offset);
      if (number != null) {
        add(number.end, 'number');
        continue;
      }
      final identifier = _identifier.matchAsPrefix(source, offset);
      if (identifier != null) {
        final word = identifier.group(0)!;
        add(
          identifier.end,
          keywords.contains(word)
              ? 'keyword'
              : types.contains(word)
              ? 'type'
              : 'plain',
        );
        continue;
      }
      add(offset + 1, _operators.contains(character) ? 'operator' : 'plain');
    }
    return tokens;
  }
}

/// Palettes exported from the real native Monaco theme definitions. The four
/// defaults are available synchronously; imported legacy palettes load once.
class _SyntaxThemeChanges extends ChangeNotifier {
  void publish() => notifyListeners();
}

abstract final class SynapseSyntaxThemes {
  static final _changes = _SyntaxThemeChanges();
  static Future<void>? _loading;
  static final _themes = <String, Map<String, Object?>>{};
  static const _dark = {
    'comment': '6A9955',
    'keyword': '569CD6',
    'type': '4EC9B0',
    'string': 'CE9178',
    'escape': 'D7BA7D',
    'number': 'B5CEA8',
    'operator': 'D4D4D4',
    'interpolation': 'CE9178',
  };

  static Future<void> ensureLoaded() => _loading ??= () async {
    try {
      final raw =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/editor/synapse-syntax-themes.json',
                ),
              )
              as Map;
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          _themes[entry.key as String] = Map<String, Object?>.from(entry.value);
        }
      }
      _changes.publish();
    } on Object {
      // Packaged defaults remain usable if an external preview lacks assets.
    }
  }();

  static Color foreground(String themeId) => Color(
    0xff000000 |
        (int.tryParse(
              _themes[themeId]?['foreground'] as String? ?? '',
              radix: 16,
            ) ??
            (themeId == 'tomorrow-night-eighties'
                ? 0xcccccc
                : themeId == 'net-theme-light'
                ? 0
                : 0xd4d4d4)),
  );

  static TextStyle style(String themeId, String kind) {
    final raw = (_themes[themeId]?['styles'] as Map?)?[kind] as Map?;
    String? color = raw?['foreground'] as String?;
    String fontStyle = raw?['fontStyle'] as String? ?? '';
    if (color == null) {
      color = _dark[kind];
      if (themeId == 'tomorrow-night-eighties') {
        color =
            const {
              'comment': '999999',
              'keyword': 'CC99CC',
              'string': '99CC99',
              'escape': '99CC99',
              'number': 'B5CEA8',
              'interpolation': '99CC99',
            }[kind] ??
            color;
      } else if (themeId == 'net-theme-dark') {
        color =
            const {
              'comment': '8C8C8C',
              'keyword': 'FF6A00',
              'string': '468DD4',
              'escape': '468DD4',
              'number': 'FFC600',
              'interpolation': '468DD4',
            }[kind] ??
            color;
        if (kind == 'keyword') fontStyle = 'bold';
      } else if (kind == 'comment') {
        fontStyle = 'italic';
      }
    }
    final parsed = int.tryParse(color ?? '', radix: 16);
    return TextStyle(
      color: parsed == null ? null : Color(0xff000000 | parsed),
      fontWeight: fontStyle.contains('bold')
          ? FontWeight.bold
          : FontWeight.normal,
      fontStyle: fontStyle.contains('italic')
          ? FontStyle.italic
          : FontStyle.normal,
      decoration: fontStyle.contains('underline')
          ? TextDecoration.underline
          : null,
    );
  }
}

class LuauSyntaxController extends TextEditingController {
  LuauSyntaxController({super.text, String themeId = 'synapse-v3'})
    : _themeId = themeId {
    SynapseSyntaxThemes._changes.addListener(_themeLoaded);
    unawaited(SynapseSyntaxThemes.ensureLoaded());
  }
  String _themeId;
  Color? _foreground;
  String? _tokenized;
  List<LuauToken> _tokens = const [];
  TextSpan? _cachedSpan;
  String? _cachedSpanTheme;
  Color? _cachedSpanForeground;
  TextStyle? _cachedSpanStyle;
  TextRange? _cachedSpanComposing;
  void _themeLoaded() {
    _cachedSpan = null;
    super.notifyListeners();
  }

  @override
  void notifyListeners() {
    _cachedSpan = null;
    super.notifyListeners();
  }

  /// Called as the source shell rebuilds, without changing text or selection.
  void useTheme(String themeId, {Color? foreground}) {
    if (_themeId == themeId && _foreground == foreground) return;
    _themeId = themeId;
    _foreground = foreground;
    _cachedSpan = null;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_tokenized != text) {
      _tokenized = text;
      _tokens = LuauSyntax.tokenize(text);
      _cachedSpan = null;
    }
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final resolvedStyle = (style ?? const TextStyle()).copyWith(
      color: _foreground ?? SynapseSyntaxThemes.foreground(_themeId),
    );
    if (_cachedSpan != null &&
        _cachedSpanTheme == _themeId &&
        _cachedSpanForeground == _foreground &&
        _cachedSpanStyle == resolvedStyle &&
        _cachedSpanComposing == composing) {
      return _cachedSpan!;
    }
    final spans = <TextSpan>[];
    for (final token in _tokens) {
      final tokenStyle = token.kind == 'plain'
          ? const TextStyle()
          : SynapseSyntaxThemes.style(_themeId, token.kind);
      final boundaries = <int>{token.start, token.end};
      if (!composing.isCollapsed && composing.isValid) {
        if (composing.start > token.start && composing.start < token.end) {
          boundaries.add(composing.start);
        }
        if (composing.end > token.start && composing.end < token.end) {
          boundaries.add(composing.end);
        }
      }
      final ordered = boundaries.toList()..sort();
      for (var i = 0; i + 1 < ordered.length; i++) {
        final start = ordered[i], end = ordered[i + 1];
        final underlined =
            !composing.isCollapsed &&
            composing.isValid &&
            start >= composing.start &&
            end <= composing.end;
        spans.add(
          TextSpan(
            text: text.substring(start, end),
            style: underlined
                ? tokenStyle.copyWith(decoration: TextDecoration.underline)
                : tokenStyle,
          ),
        );
      }
    }
    final result = TextSpan(style: resolvedStyle, children: spans);
    _cachedSpan = result;
    _cachedSpanTheme = _themeId;
    _cachedSpanForeground = _foreground;
    _cachedSpanStyle = resolvedStyle;
    _cachedSpanComposing = composing;
    return result;
  }

  @override
  void dispose() {
    SynapseSyntaxThemes._changes.removeListener(_themeLoaded);
    super.dispose();
  }
}

/// A non-interactive surface while a native editor starts or lacks a snapshot.
/// Text and token colours are shared with the editable Flutter fallback.
class LuauCodePreview extends StatelessWidget {
  const LuauCodePreview({
    super.key,
    required this.controller,
    required this.style,
    this.gutterWidth = 40,
    this.gutterColor = const Color(0xff858585),
    this.showLineNumbers = true,
    this.padding = EdgeInsets.zero,
    this.wordWrap = false,
  });
  final LuauSyntaxController controller;
  final TextStyle style;
  final double gutterWidth;
  final Color gutterColor;
  final bool showLineNumbers, wordWrap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => LayoutBuilder(
        builder: (context, constraints) {
          final code = controller.buildTextSpan(
            context: context,
            style: style,
            withComposing: false,
          );
          final gutter = showLineNumbers ? gutterWidth : 0.0;
          final painter = TextPainter(
            text: code,
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.noScaling,
          )..layout();
          final available = (constraints.maxWidth - gutter - padding.horizontal)
              .clamp(0.0, double.infinity);
          final width = wordWrap || painter.width < available
              ? available
              : painter.width;
          painter.dispose();
          return ClipRect(
            child: SingleChildScrollView(
              child: Padding(
                padding: padding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showLineNumbers)
                      SizedBox(
                        width: gutter,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                            List.generate(
                              value.text.split('\n').length,
                              (index) => '${index + 1}',
                            ).join('\n'),
                            textAlign: TextAlign.right,
                            textScaler: TextScaler.noScaling,
                            style: style.copyWith(color: gutterColor),
                          ),
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: width,
                          child: RichText(
                            text: code,
                            softWrap: wordWrap,
                            textScaler: TextScaler.noScaling,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
