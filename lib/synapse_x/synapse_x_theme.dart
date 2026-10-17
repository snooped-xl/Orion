import '../widgets/synapse_theme_surface.dart';
import 'package:flutter/material.dart';

/// Fresh WPF shell values from the pinned Synapse Framework source.
class SynapseXTheme {
  SynapseXTheme(this.preferences);
  final Map<String, Object?> preferences;
  static const defaults = <String, int>{
    'windowBg': 0xff333333,
    'panelBg': 0xff3c3c3c,
    'text': 0xffffffff,
    'buttonBg': 0xff3c3c3c,
    'buttonHoverBg': 0xff464646,
    'buttonActiveBg': 0xff323232,
    'buttonBorder': 0x00000000,
    'buttonText': 0xffffffff,
    'tabBg': 0xff1e1e1e,
    'tabActiveBg': 0xff1e1e1e,
    'tabBorder': 0xff1e1e1e,
    'tabActiveBorder': 0xff1e1e1e,
    'tabText': 0xffc0c0c0,
    'editorBg': 0xff1e1e1e,
    'listHoverBg': 0xff333333,
    'listText': 0xffc0c0c0,
    'iconColor': 0xffc0c0c0,
  };

  /// Source JSON files are plain theme objects; the community exporter also
  /// accepts a `theme` envelope. Validate the entire file before committing it.
  static Map<String, int> decodeColors(Object? json) {
    final raw = json is Map && json['theme'] is Map ? json['theme'] : json;
    if (raw is! Map) throw const FormatException('Invalid theme JSON.');
    final result = Map<String, int>.of(defaults);
    var found = false;
    for (final key in defaults.keys) {
      final value = raw[key];
      if (value == null) continue;
      found = true;
      if (value == 'transparent' && key == 'buttonBorder') {
        result[key] = 0;
      } else if (value is String &&
          RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
        result[key] = 0xff000000 | int.parse(value.substring(1), radix: 16);
      } else {
        throw FormatException('Invalid $key color.');
      }
    }
    if (!found) throw const FormatException('No Synapse X colors found.');
    return result;
  }

  Color color(String key) {
    final value = preferences['theme.$key'];
    return Color(value is int ? value : defaults[key] ?? 0xffffffff);
  }

  Color get window => color('windowBg');
  Color get panel => color('panelBg');
  Color get text => color('text');
  Color get editor => color('editorBg');
  static String hex(Color color) =>
      '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
  static TextStyle type(
    double size, {
    Color color = Colors.white,
    FontWeight weight = FontWeight.w400,
    bool segoe = false,
    double? height,
  }) => TextStyle(
    fontFamily: 'SynapseInter',
    fontSize: size,
    fontWeight: weight,
    letterSpacing: 0,
    color: color,
    height: height,
  );
}

/// Flat WPF button with source hover/press colors and no Material splash.
class XButton extends StatefulWidget {
  const XButton(
    this.label, {
    super.key,
    required this.onPressed,
    required this.theme,
    this.size = 14,
    this.border,
    this.background,
    this.segoe = false,
    this.tooltip,
    this.weight = FontWeight.w400,
    this.horizontalPadding = 4,
    this.wrap = false,
    this.lineHeight,
  });
  final String label;
  final VoidCallback? onPressed;
  final SynapseXTheme theme;
  final double size;
  final Color? border, background;
  final bool segoe;
  final String? tooltip;
  final FontWeight weight;
  final double horizontalPadding;
  final bool wrap;
  final double? lineHeight;
  @override
  State<XButton> createState() => _XButtonState();
}

class _XButtonState extends State<XButton> {
  bool hover = false, pressed = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final element = SynapseThemeElementStyleScope.maybeOf(context);
    final foreground = element?.foreground == null
        ? widget.theme.color('buttonText')
        : Color(element!.foreground!);
    final fill = element?.image?.isValid == true && element!.image!.opacity > 0
        ? Colors.transparent
        : element?.fill == null
        ? null
        : Color(element!.fill!);
    final border = element?.border == null
        ? widget.border ?? widget.theme.color('buttonBorder')
        : Color(element!.border!);
    final label = Text(
      widget.label,
      maxLines: widget.wrap ? null : 1,
      overflow: widget.wrap ? TextOverflow.visible : TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style:
          SynapseXTheme.type(
            widget.size,
            color: enabled ? foreground : foreground.withValues(alpha: .5),
            segoe: widget.segoe,
            weight: widget.weight,
            height: widget.lineHeight,
          ).copyWith(
            fontFamily: SynapseThemeElementStyleScope.fontFamilyOf(context),
          ),
    );
    final child = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() {
        hover = false;
        pressed = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => pressed = true),
        onPointerUp: (_) => setState(() => pressed = false),
        onPointerCancel: (_) => setState(() => pressed = false),
        child: TextButton(
          onPressed: widget.onPressed,
          style:
              TextButton.styleFrom(
                // CSS border-box buttons reserve one pixel for their border.
                padding: EdgeInsets.symmetric(
                  horizontal: widget.horizontalPadding + 1,
                  vertical: 1,
                ),
                visualDensity: VisualDensity.standard,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: foreground,
                disabledForegroundColor: foreground.withValues(alpha: .5),
                backgroundColor:
                    fill ??
                    (enabled
                        ? pressed
                              ? widget.theme.color('buttonActiveBg')
                              : hover
                              ? widget.theme.color('buttonHoverBg')
                              : widget.background ??
                                    widget.theme.color('buttonBg')
                        : (widget.background ?? widget.theme.color('buttonBg'))
                              .withValues(alpha: .5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(element?.radius ?? 0),
                  side: BorderSide(color: border),
                ),
              ).copyWith(
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              ),
          child: widget.wrap
              ? OverflowBox(
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: label,
                )
              : label,
        ),
      ),
    );
    return widget.tooltip == null
        ? child
        : Tooltip(message: widget.tooltip!, child: child);
  }
}
