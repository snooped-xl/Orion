import 'package:flutter/material.dart';

import '../models/local_script.dart';
import '../theme/orion_theme.dart';

const specialScriptColors = <Color>[
  Color(0xffffffff),
  Color(0xff87b8ff),
  Color(0xff86daac),
  Color(0xffff9a9a),
  Color(0xffffffff),
];

String scriptCodeLabel(ScriptColorCode code) => switch (code) {
  ScriptColorCode.none => 'None',
  ScriptColorCode.white => 'White',
  ScriptColorCode.blue => 'Blue',
  ScriptColorCode.green => 'Green',
  ScriptColorCode.red => 'Red',
  ScriptColorCode.special => 'Special',
};

Color scriptCodeColor(ScriptColorCode code, OrionColors colors) =>
    switch (code) {
      ScriptColorCode.none => colors.ink,
      ScriptColorCode.white => Colors.white,
      ScriptColorCode.blue =>
        colors.isLight ? const Color(0xff245fa5) : const Color(0xff87b8ff),
      ScriptColorCode.green =>
        colors.isLight ? const Color(0xff276a47) : const Color(0xff86daac),
      ScriptColorCode.red =>
        colors.isLight ? const Color(0xffaf3945) : const Color(0xffff9a9a),
      ScriptColorCode.special => colors.ink,
    };

/// Only the small glyph surface repaints; the list and editor retain their
/// layout while Special's seamlessly tiled white/blue/green/red gradient moves.
class ScriptCodeText extends StatefulWidget {
  const ScriptCodeText({
    super.key,
    required this.text,
    this.code = ScriptColorCode.none,
    this.style,
    this.reducedMotion = false,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String text;
  final ScriptColorCode code;
  final TextStyle? style;
  final bool reducedMotion;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  State<ScriptCodeText> createState() => _ScriptCodeTextState();
}

class _ScriptCodeTextState extends State<ScriptCodeText>
    with SingleTickerProviderStateMixin {
  AnimationController? _phase;

  bool get _moving =>
      widget.code == ScriptColorCode.special &&
      !widget.reducedMotion &&
      !MediaQuery.disableAnimationsOf(context);

  void _syncMotion() {
    if (_moving) {
      _phase ??= AnimationController(
        vsync: this,
        duration: const Duration(seconds: 8),
      );
      if (!_phase!.isAnimating) _phase!.repeat();
    } else {
      _phase?.stop();
      if (_phase != null && _phase!.value != 0) _phase!.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant ScriptCodeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void dispose() {
    _phase?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    final special = widget.code == ScriptColorCode.special;
    final text = Text(
      widget.text,
      key: const ValueKey('script-code-text'),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      style: (widget.style ?? OrionType.label).copyWith(
        color: special ? Colors.white : scriptCodeColor(widget.code, colors),
      ),
    );
    if (!special) return text;
    Widget gradient(double phase, Widget text) => ShaderMask(
      key: const ValueKey('script-code-gradient'),
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        colors: specialScriptColors,
        tileMode: TileMode.repeated,
        transform: _ScriptGradientSlide(phase),
      ).createShader(bounds),
      child: text,
    );
    return RepaintBoundary(
      child: _moving
          ? AnimatedBuilder(
              animation: _phase!,
              child: text,
              builder: (_, child) => gradient(_phase!.value, child!),
            )
          : gradient(0, text),
    );
  }
}

class _ScriptGradientSlide extends GradientTransform {
  const _ScriptGradientSlide(this.phase);
  final double phase;
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * phase, 0, 0);
}

class ScriptCodeSwatch extends StatelessWidget {
  const ScriptCodeSwatch({super.key, required this.code, this.size = 14});
  final ScriptColorCode code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    if (code == ScriptColorCode.none) {
      return SizedBox.square(
        dimension: size,
        child: Icon(
          Icons.format_color_reset_rounded,
          size: size,
          color: colors.muted,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: code == ScriptColorCode.special
            ? null
            : scriptCodeColor(code, colors),
        gradient: code == ScriptColorCode.special
            ? const LinearGradient(colors: specialScriptColors)
            : null,
        border: Border.all(color: colors.outline(.7), width: .67),
      ),
    );
  }
}
