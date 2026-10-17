import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/monaco_editor_service.dart';

/// The original V3 cold loading screen, over a mounted and obscured editor.
class V3Entrance extends StatefulWidget {
  const V3Entrance({
    super.key,
    required this.child,
    required this.play,
    required this.reducedMotion,
    this.editorService,
    required this.onCompleted,
    required this.cornerRadius,
    this.borderColor = const Color(0xff4b4d4c),
  });

  final Widget child;
  final bool play;
  final bool reducedMotion;
  final MonacoEditorService? editorService;
  final VoidCallback onCompleted;
  final double cornerRadius;
  final Color borderColor;

  @override
  State<V3Entrance> createState() => _V3EntranceState();
}

class _V3EntranceState extends State<V3Entrance> with TickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..addStatusListener(_fadeStatus);
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  Timer? _hold;
  bool _running = false;
  bool _revealing = false;

  @override
  void initState() {
    super.initState();
    if (widget.play) _start();
  }

  void _start() {
    _hold?.cancel();
    _running = true;
    _revealing = false;
    _fade.value = 0;
    _spin.value = 0;
    widget.editorService?.setObscured(true, owner: 'v3-loading');
    if (!widget.reducedMotion) _spin.repeat();
    _hold = Timer(const Duration(seconds: 2), () {
      _hold = null;
      if (!mounted || !_running) return;
      _revealing = true;
      if (widget.reducedMotion) {
        _finish();
      } else {
        _fade.forward();
      }
    });
  }

  void _fadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finish();
  }

  void _finish({bool notify = true}) {
    if (!_running) return;
    _hold?.cancel();
    _hold = null;
    _running = false;
    _revealing = false;
    _spin.stop();
    _fade.stop();
    widget.editorService?.setObscured(false, owner: 'v3-loading');
    if (mounted) setState(() {});
    if (notify) widget.onCompleted();
  }

  @override
  void didUpdateWidget(covariant V3Entrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editorService != widget.editorService && _running) {
      oldWidget.editorService?.setObscured(false, owner: 'v3-loading');
      widget.editorService?.setObscured(true, owner: 'v3-loading');
    }
    if (oldWidget.play != widget.play) {
      if (widget.play) {
        _start();
      } else {
        _finish(notify: false);
      }
    }
    if (oldWidget.reducedMotion != widget.reducedMotion && _running) {
      if (widget.reducedMotion) {
        _spin.stop();
        if (_revealing) _finish();
      } else {
        _spin.repeat();
      }
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    if (_running) {
      widget.editorService?.setObscured(false, owner: 'v3-loading');
    }
    _fade.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      IgnorePointer(
        ignoring: _running,
        child: ExcludeFocus(
          excluding: _running,
          child: ExcludeSemantics(excluding: _running, child: widget.child),
        ),
      ),
      if (_running)
        Positioned.fill(
          child: Semantics(
            label: 'Loading Synapse V3',
            liveRegion: true,
            child: AbsorbPointer(
              child: AnimatedBuilder(
                animation: _fade,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    math.max(0, widget.cornerRadius),
                  ),
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        math.max(0, widget.cornerRadius),
                      ),
                      border: Border.all(color: widget.borderColor),
                    ),
                    child: ExcludeSemantics(child: _loadingScreen()),
                  ),
                ),
                builder: (context, child) => Opacity(
                  key: const ValueKey('v3-loading-opacity'),
                  opacity: 1 - Curves.easeOut.transform(_fade.value),
                  child: child,
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _loadingScreen() => LayoutBuilder(
    builder: (context, constraints) => Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/synapse_v3/v3-loading-bg.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
        Positioned(
          left: constraints.maxWidth / 2 - 90.5,
          top: constraints.maxHeight / 2 - 42.5,
          width: 181,
          height: 38,
          child: Stack(
            key: const ValueKey('v3-loading-logo'),
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Transform.translate(
                offset: const Offset(0, 4),
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 8.5, sigmaY: 8.5),
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Color(0x6e000000),
                      BlendMode.srcIn,
                    ),
                    child: _logo(),
                  ),
                ),
              ),
              _logo(),
            ],
          ),
        ),
        if (!widget.reducedMotion)
          Positioned(
            left: constraints.maxWidth / 2 - 14.5,
            top: constraints.maxHeight / 2 + 12.5,
            width: 29,
            height: 29,
            child: AnimatedBuilder(
              animation: _spin,
              child: const CustomPaint(
                key: ValueKey('v3-loading-spinner'),
                painter: _V3SpinnerPainter(),
              ),
              builder: (context, child) => Transform.rotate(
                angle: _spin.value * math.pi * 2,
                child: child,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _logo() => Image.asset(
    'assets/synapse_v3/v3-logo.png',
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
  );
}

class _V3SpinnerPainter extends CustomPainter {
  const _V3SpinnerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).deflate(1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xe6ffffff);
    canvas.drawOval(bounds, paint);
    paint.color = const Color(0xff8e4b0c);
    canvas.drawArc(bounds, -math.pi * 3 / 4, math.pi / 2, false, paint);
  }

  @override
  bool shouldRepaint(_V3SpinnerPainter oldDelegate) => false;
}
