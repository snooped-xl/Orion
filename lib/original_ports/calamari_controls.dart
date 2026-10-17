import 'package:flutter/material.dart';

abstract final class CalamariSource {
  static const window = Color(0xfff5f5f5);
  static const title = Color(0xffececec);
  static TextStyle type(
    double size, {
    Color color = const Color(0xff111111),
    FontWeight weight = FontWeight.normal,
  }) => TextStyle(
    fontFamily: 'OriginalArial',
    fontFamilyFallback: const ['OriginalSymbols', 'OriginalEmoji'],
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: 0,
    height: 1.15,
  );
}

/// macOS-style source controls retain their static hover/pressed appearance.
class CalamariButton extends StatelessWidget {
  const CalamariButton(
    this.label, {
    super.key,
    this.onPressed,
    this.selected = false,
    this.child,
    this.link = false,
    this.tooltip,
    this.radius = 5,
    this.border = const Color(0xffbdbdbd),
    this.background = const Color(0xfffafafa),
    this.size = 14,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool selected, link;
  final Widget? child;
  final String? tooltip;
  final double radius, size;
  final Color border, background;
  @override
  Widget build(BuildContext context) {
    Widget control = Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: MouseRegion(
        cursor: onPressed != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: link
                  ? Colors.transparent
                  : selected
                  ? null
                  : background,
              border: link
                  ? null
                  : Border.all(
                      color: selected ? const Color(0xff0873c9) : border,
                    ),
              borderRadius: BorderRadius.circular(radius),
              gradient: selected
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xff50a5f5),
                        Color(0xff1688e7),
                        Color(0xff0874d2),
                      ],
                      stops: [0, .5, 1],
                    )
                  : null,
            ),
            child: Padding(
              padding: EdgeInsets.all(link ? 0 : 1),
              child: Center(
                child:
                    child ??
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style:
                          CalamariSource.type(
                            size,
                            color: link
                                ? const Color(0xff0000ee)
                                : selected
                                ? Colors.white
                                : const Color(0xff171717),
                          ).copyWith(
                            decoration: link ? TextDecoration.underline : null,
                          ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) control = Tooltip(message: tooltip!, child: control);
    return control;
  }
}

class CalamariInput extends StatelessWidget {
  const CalamariInput({
    super.key,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.rounded = true,
  });
  final TextEditingController controller;
  final String? hint;
  final bool obscure, rounded;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: rounded ? const Color(0xfffafafa) : Colors.white,
      border: Border.all(color: const Color(0xffbdbdbd)),
      borderRadius: BorderRadius.circular(rounded ? 5 : 0),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(rounded ? 5 : 0),
      child: Align(
        alignment: rounded ? Alignment.centerLeft : Alignment.topLeft,
        child: TextField(
          controller: controller,
          obscureText: obscure,
          obscuringCharacter: '•',
          style: CalamariSource.type(14, color: const Color(0xff222222)),
          cursorColor: const Color(0xff222222),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: CalamariSource.type(14, color: const Color(0x99ffffff)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 3,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          textAlignVertical: rounded
              ? TextAlignVertical.center
              : TextAlignVertical.top,
        ),
      ),
    ),
  );
}

/// Original inline AXAML shopping/group symbols, without a replacement icon set.
class CalamariLinkIcon extends StatelessWidget {
  const CalamariLinkIcon({super.key, this.group = false});
  final bool group;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 14,
    height: 14,
    child: CustomPaint(painter: _CalamariLinkPainter(group)),
  );
}

class _CalamariLinkPainter extends CustomPainter {
  const _CalamariLinkPainter(this.group);
  final bool group;
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0xff0000ee);
    if (group) {
      canvas.drawOval(const Rect.fromLTWH(4, 0, 6, 6), fill);
      canvas.drawOval(const Rect.fromLTWH(0, 4, 5, 5), fill);
      canvas.drawOval(const Rect.fromLTWH(9, 4, 5, 5), fill);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(2, 9, 10, 5),
          const Radius.circular(2),
        ),
        fill,
      );
    } else {
      final stroke = Paint()
        ..color = const Color(0xff0000ee)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      final path = Path()
        ..moveTo(1, 1)
        ..lineTo(4, 1)
        ..lineTo(6, 10)
        ..lineTo(13, 10)
        ..lineTo(15, 3)
        ..lineTo(5, 3);
      canvas.drawPath(path, stroke);
      canvas.drawCircle(const Offset(8, 13), 1, stroke);
      canvas.drawCircle(const Offset(12, 13), 1, stroke);
    }
  }

  @override
  bool shouldRepaint(_CalamariLinkPainter oldDelegate) =>
      group != oldDelegate.group;
}
