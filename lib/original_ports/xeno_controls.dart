import 'package:flutter/material.dart';

TextStyle xenoType(
  double size, {
  Color color = Colors.white,
  FontWeight weight = FontWeight.w400,
  bool mono = false,
  String? family,
}) => TextStyle(
  // The original Avalonia Linux font resolver maps its named Windows faces
  // (Consolas/Cascadia/Franklin) to Noto Sans in these support controls.
  fontFamily: family ?? 'OriginalXenoUI',
  fontSize: size,
  color: color,
  fontWeight: weight,
  height: (size * 1.362).ceil() / size,
);

class XenoIconButton extends StatefulWidget {
  const XenoIconButton({
    super.key,
    required this.tooltip,
    this.asset,
    this.child,
    this.onPressed,
    this.width = 34,
    this.height = 34,
    this.imageSize = 25,
  });
  final String tooltip;
  final String? asset;
  final Widget? child;
  final VoidCallback? onPressed;
  final double width, height, imageSize;
  @override
  State<XenoIconButton> createState() => _XenoIconButtonState();
}

class _XenoIconButtonState extends State<XenoIconButton> {
  bool hover = false, pressed = false;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: Semantics(
      button: true,
      label: widget.tooltip,
      enabled: widget.onPressed != null,
      child: MouseRegion(
        cursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() {
          hover = false;
          pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          onTapDown: (_) => setState(() => pressed = true),
          onTapUp: (_) => setState(() => pressed = false),
          onTapCancel: () => setState(() => pressed = false),
          child: Container(
            width: widget.width,
            height: widget.height,
            alignment: Alignment.center,
            color: widget.onPressed == null
                ? Colors.transparent
                : pressed
                ? const Color(0xff5a5a5a)
                : hover
                ? const Color(0xff474747)
                : Colors.transparent,
            child: Opacity(
              opacity: widget.onPressed == null ? .52 : 1,
              child:
                  widget.child ??
                  Image.asset(
                    'assets/original_xeno/${widget.asset}.png',
                    width: widget.imageSize,
                    height: widget.imageSize,
                    filterQuality: FilterQuality.high,
                  ),
            ),
          ),
        ),
      ),
    ),
  );
}

class XenoTextButton extends StatefulWidget {
  const XenoTextButton({
    super.key,
    required this.label,
    required this.width,
    required this.height,
    this.onPressed,
    this.fontSize = 13,
  });
  final String label;
  final double width, height, fontSize;
  final VoidCallback? onPressed;
  @override
  State<XenoTextButton> createState() => _XenoTextButtonState();
}

class _XenoTextButtonState extends State<XenoTextButton> {
  bool hover = false, pressed = false;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    enabled: widget.onPressed != null,
    child: MouseRegion(
      cursor: widget.onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() {
        hover = false;
        pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: (_) => setState(() => pressed = true),
        onTapUp: (_) => setState(() => pressed = false),
        onTapCancel: () => setState(() => pressed = false),
        child: Container(
          width: widget.width,
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: widget.onPressed == null
                ? const Color(0xff1a1a1a)
                : pressed
                ? const Color(0xff414141)
                : hover
                ? const Color(0xff2d2d2d)
                : const Color(0xff1a1a1a),
            border: Border.all(color: const Color(0xff333333)),
          ),
          child: Text(
            widget.label,
            style: xenoType(
              widget.fontSize,
              mono: true,
              color: widget.onPressed == null
                  ? const Color(0xff777777)
                  : Colors.white,
            ),
          ),
        ),
      ),
    ),
  );
}
