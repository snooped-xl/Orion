import 'package:flutter/material.dart';

const awpBackground = Color(0xff1f1f1f);
const awpEditorBackground = Color(0xff191818);
const awpPanel = Color(0xff282828);
const awpBorder = Color(0xff2c2c2c);
const awpText = Color(0xffc5c5c5);
const awpMuted = Color(0xff808080);

TextStyle awpType(
  double size, {
  Color color = awpText,
  FontWeight weight = FontWeight.w400,
  double? spacing,
  bool mono = false,
  double? height,
}) => TextStyle(
  fontFamily: mono ? 'SynapseXMono' : 'OriginalAwpUI',
  fontSize: size,
  color: color,
  fontWeight: weight,
  letterSpacing: spacing ?? 0,
  height: height ?? (size * 1.21).ceil() / size,
);

Widget awpIcon(String name, {double size = 14, Color color = awpMuted}) =>
    Image.asset(
      'assets/original_awp/$name.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.high,
    );

/// Avalonia's original flat/button styles have immediate pointer states and no ink.
class AwpButton extends StatefulWidget {
  const AwpButton({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    this.onDoubleTap,
    this.tooltip,
    this.height = 28,
    this.width,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    this.flat = false,
    this.execute = false,
    this.selected = false,
    this.close = false,
    this.radius = 4,
    this.fontSize = 12,
    this.fontWeight = FontWeight.w400,
    this.color,
    this.background,
    this.border,
    this.alignment = Alignment.center,
    this.icon,
    this.iconSize = 14,
  });
  final String? label, tooltip, icon;
  final Widget? child;
  final VoidCallback? onPressed, onDoubleTap;
  final double height, radius, fontSize, iconSize;
  final double? width;
  final EdgeInsets padding;
  final bool flat, execute, selected, close;
  final FontWeight fontWeight;
  final Color? color, background, border;
  final Alignment alignment;
  @override
  State<AwpButton> createState() => _AwpButtonState();
}

class _AwpButtonState extends State<AwpButton> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final w = widget;
    final enabled = w.onPressed != null;
    final background = !enabled && w.execute
        ? awpEditorBackground
        : hover && enabled
        ? w.close
              ? const Color(0xffc0392b)
              : w.flat
              ? awpPanel
              : const Color(0x99313131)
        : w.background ??
              (w.selected
                  ? const Color(0xff2d2d2d)
                  : w.flat
                  ? Colors.transparent
                  : const Color(0x99282828));
    final foreground =
        w.color ??
        (!enabled
            ? w.execute
                  ? const Color(0xff414141)
                  : const Color(0x4d808080)
            : hover
            ? w.close
                  ? Colors.white
                  : w.flat
                  ? awpText
                  : const Color(0xff8d8d8d)
            : w.selected
            ? awpText
            : awpMuted);
    Widget result = Semantics(
      button: true,
      enabled: enabled,
      label: w.tooltip ?? w.label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: GestureDetector(
          onTap: w.onPressed,
          onDoubleTap: w.onDoubleTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: w.width,
            height: w.height,
            padding: w.padding,
            alignment: w.alignment,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(w.radius),
              border: w.flat && w.border == null && !w.selected
                  ? null
                  : Border.all(
                      color:
                          w.border ??
                          (!enabled && w.execute
                              ? const Color(0xff232222)
                              : w.selected
                              ? const Color(0xff3a3a3a)
                              : const Color(0x992c2c2c)),
                    ),
            ),
            child: DefaultTextStyle(
              style: awpType(
                w.fontSize,
                color: foreground,
                weight: w.fontWeight,
              ),
              child: IconTheme(
                data: IconThemeData(color: foreground, size: 14),
                child:
                    w.child ??
                    (w.icon == null
                        ? Text(w.label ?? '', maxLines: 1)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              awpIcon(
                                w.icon!,
                                size: w.iconSize,
                                color: foreground,
                              ),
                              if (w.label != null) ...[
                                const SizedBox(width: 6),
                                Text(w.label!, maxLines: 1),
                              ],
                            ],
                          )),
              ),
            ),
          ),
        ),
      ),
    );
    if (w.tooltip != null) result = Tooltip(message: w.tooltip!, child: result);
    return result;
  }
}

class AwpInput extends StatelessWidget {
  const AwpInput({
    super.key,
    required this.controller,
    this.hint,
    this.password = false,
    this.onSubmitted,
    this.autofocus = false,
  });
  final TextEditingController controller;
  final String? hint;
  final bool password, autofocus;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    child: TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: password,
      obscuringCharacter: '●',
      onSubmitted: onSubmitted,
      cursorColor: awpText,
      textAlignVertical: TextAlignVertical.center,
      style: awpType(12, height: 1.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: awpType(12, color: const Color(0x99ffffff), height: 1.5),
        isDense: true,
        visualDensity: VisualDensity.standard,
        filled: true,
        fillColor: awpPanel,
        contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: awpBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Color(0xff444444)),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: awpBorder),
        ),
      ),
    ),
  );
}
