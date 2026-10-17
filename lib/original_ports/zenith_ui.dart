import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';
import 'zenith_icons_data.dart';

const zenithBackground = Color(0xff0a0a0a);
const zenithCard = Color(0x08ffffff);
const zenithMuted = Color(0xe69a9a9a);
const zenithSecondary = Color(0xe6ffffff);
const zenithCurve = Cubic(.4, 0, .2, 1);
TextStyle zenithText(
  double size, {
  Color color = zenithSecondary,
  FontWeight weight = FontWeight.w400,
  double height = 1.2,
  String family = 'OriginalNunito',
}) => TextStyle(
  fontFamily: family,
  fontSize: size,
  fontWeight: family == 'OriginalNunito' && weight.value >= 600
      ? FontWeight.w700
      : weight,
  fontFamilyFallback: const ['OriginalSymbols', 'OriginalEmoji'],
  letterSpacing: 0,
  height: height,
  color: color,
);

class ZenithGlyph extends StatelessWidget {
  const ZenithGlyph(
    this.name, {
    super.key,
    this.size = 24,
    this.color = const Color(0xbf9a9a9a),
    this.stroke = false,
  });
  final String name;
  final double size;
  final Color color;
  final bool stroke;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _Glyph(name, color, stroke)),
  );
}

class _Glyph extends CustomPainter {
  _Glyph(this.name, this.color, this.stroke);
  final String name;
  final Color color;
  final bool stroke;
  static final paths = <String, Path>{};
  @override
  void paint(Canvas canvas, Size size) {
    final viewport = name == 'Close' ? 26.0 : 24.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = switch (name) {
        'File' || 'Folder' || 'Chevron' => 2,
        'ChevronDown' || 'ChevronUp' => 2.2,
        _ => 1.8,
      }
      ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (name != 'Chevron') {
      canvas.scale(size.width / viewport, size.height / viewport);
    }
    if (name == 'Help') {
      canvas.drawCircle(
        const Offset(12, 12),
        10,
        paint..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        parseSvgPathData('M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3M12 17L12.01 17'),
        paint,
      );
      return;
    }
    final data = zenithPaths['Zenith${name}Glyph'];
    if (data == null) return;
    final path = paths.putIfAbsent(
      name,
      () => parseSvgPathData(data)..fillType = PathFillType.evenOdd,
    );
    if (name == 'Chevron') {
      // This source Path uses Stretch.Uniform directly in a 14px slot rather
      // than the 24px Canvas/Viewbox used by the other icon controls.
      final bounds = path.getBounds();
      final scale = (size.height - 2) / bounds.height;
      canvas.translate((size.width - bounds.width * scale) / 2, 1);
      canvas.scale(scale);
      paint.strokeWidth = 2 / scale;
      canvas.drawPath(path.shift(-bounds.topLeft), paint);
    } else {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_Glyph old) =>
      name != old.name || color != old.color || stroke != old.stroke;
}

class ZenithButton extends StatefulWidget {
  const ZenithButton(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.iconSize,
    this.iconStroke = false,
    this.alignment = Alignment.center,
    this.width,
    this.height = 36,
    this.action = false,
    this.chrome = false,
    this.hoverBackground,
    this.hoverForeground,
    this.pressedBackground,
    this.fontWeight,
    this.background = const Color(0x13ffffff),
    this.radius = 8,
    this.fontSize = 14,
    this.color = zenithSecondary,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.blobColors,
    this.blobOffset,
  });
  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final double? iconSize;
  final bool iconStroke;
  final Alignment alignment;
  final double? width;
  final double height, radius, fontSize;
  final bool action, chrome;
  final Color? hoverBackground, pressedBackground, hoverForeground;
  final FontWeight? fontWeight;
  final Color background, color;
  final EdgeInsets padding;
  final List<Color>? blobColors;
  final Offset? blobOffset;
  @override
  State<ZenithButton> createState() => _ZenithButtonState();
}

class _ZenithButtonState extends State<ZenithButton> {
  bool hover = false, pressed = false;
  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final foreground = hover && widget.onPressed != null
        ? widget.hoverForeground ?? Colors.white
        : widget.color;
    final text = TextPainter(
      text: TextSpan(text: widget.label, style: zenithText(widget.fontSize)),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final naturalWidth =
        text.width +
        widget.padding.horizontal +
        (widget.icon == null
            ? 0
            : (widget.iconSize ?? (widget.action ? 24 : 16)) +
                  (widget.label.isEmpty ? 0 : 6));
    return SizedBox(
      width: widget.width ?? naturalWidth.ceilToDouble(),
      height: widget.height,
      child: MouseRegion(
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() {
          hover = false;
          pressed = false;
        }),
        child: TextButton(
          onPressed: widget.onPressed,
          onHover: (value) {
            if (hover != value) setState(() => hover = value);
          },
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.standard,
            splashFactory: NoSplash.splashFactory,
            overlayColor: Colors.transparent,
            foregroundColor: foreground,
            backgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(widget.radius),
            ),
          ),
          child: Listener(
            onPointerDown: (_) => setState(() => pressed = true),
            onPointerUp: (_) => setState(() => pressed = false),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedContainer(
                    duration: reduced
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    color: widget.action
                        ? widget.onPressed == null
                              ? const Color(0x137c8293)
                              : pressed
                              ? const Color(0x307c8293)
                              : hover
                              ? const Color(0x207c8293)
                              : const Color(0x137c8293)
                        : widget.chrome
                        ? Colors.transparent
                        : pressed && widget.pressedBackground != null
                        ? widget.pressedBackground!
                        : hover
                        ? widget.hoverBackground ?? const Color(0x20ffffff)
                        : widget.background,
                  ),
                  if (widget.blobColors != null)
                    Positioned(
                      left: widget.blobOffset?.dx ?? -12,
                      top: widget.blobOffset?.dy ?? 17,
                      width: 46,
                      height: 36,
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: hover || pressed ? 1 : 0,
                          duration: reduced
                              ? Duration.zero
                              : const Duration(milliseconds: 300),
                          child: AnimatedScale(
                            scale: pressed
                                ? 1.05
                                : hover
                                ? 1
                                : .9,
                            duration: reduced
                                ? Duration.zero
                                : const Duration(milliseconds: 300),
                            child: ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(
                                sigmaX: 8,
                                sigmaY: 8,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(23),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: widget.blobColors!,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: widget.padding,
                    child: Align(
                      alignment: widget.alignment,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            ZenithGlyph(
                              widget.icon!,
                              size:
                                  widget.iconSize ?? (widget.action ? 24 : 16),
                              stroke: widget.iconStroke,
                              color: foreground,
                            ),
                            if (widget.label.isNotEmpty)
                              const SizedBox(width: 6),
                          ],
                          if (widget.label.isNotEmpty)
                            Flexible(
                              child: Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: zenithText(
                                  widget.fontSize,
                                  color: foreground,
                                  weight:
                                      widget.fontWeight ??
                                      (widget.action
                                          ? FontWeight.w500
                                          : FontWeight.w400),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ZenithFade extends StatelessWidget {
  const ZenithFade({
    super.key,
    required this.animation,
    required this.child,
    this.delay = 0,
    this.duration = .3,
    this.offset = 3,
    this.css = false,
  });
  final Animation<double> animation;
  final Widget child;
  final double delay, duration, offset;
  final bool css;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (_, child) {
      final seconds = animation.value * .65;
      final progress = ((seconds - delay) / duration).clamp(0.0, 1.0);
      final t = (css ? const Cubic(0, 0, .58, 1) : Curves.easeOutCubic)
          .transform(progress);
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, offset * (1 - t)),
          child: child,
        ),
      );
    },
  );
}

Widget zenithPanel(
  Widget child, {
  EdgeInsets padding = EdgeInsets.zero,
  double radius = 12,
  Color color = zenithCard,
  Key? key,
}) => Container(
  key: key,
  padding: padding,
  decoration: BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
  ),
  child: child,
);

Widget zenithHeader(String title, String subtitle) => zenithPanel(
  Stack(
    children: [
      Positioned(
        right: -30,
        top: -30,
        width: 288,
        height: 288,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  const Color(0xff39a2ff).withValues(alpha: .09),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: zenithText(20, color: Colors.white)),
              const SizedBox(height: 4),
              Text(subtitle, style: zenithText(14, color: zenithMuted)),
            ],
          ),
        ),
      ),
    ],
  ),
);

class ZenithToggle extends StatelessWidget {
  const ZenithToggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    button: true,
    child: SizedBox(
      width: 48,
      height: 32,
      child: InkWell(
        onTap: () => onChanged(!value),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: Align(
          alignment: Alignment.centerRight,
          child: AnimatedContainer(
            width: 40,
            height: 20,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              color: value ? const Color(0xff0078d4) : Colors.transparent,
              border: Border.all(
                color: value
                    ? const Color(0xff0078d4)
                    : const Color(0xff8a8a8a),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: AnimatedAlign(
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 100),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? Colors.white : const Color(0xff8a8a8a),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
