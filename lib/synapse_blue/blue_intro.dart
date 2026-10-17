import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../services/monaco_editor_service.dart';
import '../services/native_window_service.dart';
import 'blue_icon.dart';
import 'blue_theme.dart';

/// Source Blue initialization timeline, including its native window morph.
class BlueEntrance extends StatefulWidget {
  const BlueEntrance({
    super.key,
    required this.child,
    required this.palette,
    required this.play,
    required this.reducedMotion,
    required this.nativeWindow,
    required this.resizable,
    required this.onCompleted,
    this.editorService,
    this.family = 'SynapseInter',
    this.cornerRadius = 0,
    this.targetSize = const Size(714, 393),
  });
  final Widget child;
  final BluePalette palette;
  final bool play, reducedMotion, nativeWindow, resizable;
  final VoidCallback onCompleted;
  final MonacoEditorService? editorService;
  final String family;
  final double cornerRadius;
  final Size targetSize;
  @override
  State<BlueEntrance> createState() => _BlueEntranceState();
}

class _BlueEntranceState extends State<BlueEntrance>
    with TickerProviderStateMixin {
  late final _progress = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  late final _morph =
      AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 580),
        )
        ..addListener(_resize)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) unawaited(_finish());
        });
  late final _content = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 440),
  );
  late final _secondary = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  final _timers = <Timer>[];
  bool _running = false, _finishing = false;
  Future<void>? _resizeDrain;
  Size? _queuedSize;
  Future<Offset?>? _windowCenter;
  static const _ease = Cubic(.4, 0, .2, 1);

  @override
  void initState() {
    super.initState();
    if (!widget.play) return;
    _running = true;
    if (widget.nativeWindow) {
      _windowCenter = windowManager
          .getBounds()
          .then<Offset?>((bounds) => bounds.center)
          .catchError((Object _) => null);
    }
    widget.editorService?.setObscured(true, owner: 'blue-loading');
    _later(680, () {
      if (widget.reducedMotion) {
        _content.value = 1;
      } else {
        _content.forward();
      }
    });
    _later(820, () {
      if (widget.reducedMotion) {
        _secondary.value = 1;
      } else {
        _secondary.forward();
      }
    });
    _later(800, () {
      if (!widget.reducedMotion) _progress.forward();
    });
    if (widget.reducedMotion) {
      for (var i = 1; i <= 3; i++) {
        _later(800 + i * 2000, () {
          _progress.value = i / 3;
          if (i == 3) unawaited(_finish());
        });
      }
    } else {
      _later(6820, () => _exit.forward());
      _later(7340, () => _morph.forward());
    }
  }

  void _later(int milliseconds, VoidCallback action) {
    _timers.add(
      Timer(Duration(milliseconds: milliseconds), () {
        if (mounted && _running) action();
      }),
    );
  }

  void _resize() {
    if (!widget.nativeWindow || !_running) return;
    final t = _ease.transform(_morph.value);
    _queue(
      Size(
        (290 + (widget.targetSize.width - 290) * t).roundToDouble(),
        (355 + (widget.targetSize.height - 355) * t).roundToDouble(),
      ),
    );
  }

  void _queue(Size size) {
    _queuedSize = size;
    _resizeDrain ??= _drain().whenComplete(() => _resizeDrain = null);
  }

  Future<void> _drain() async {
    try {
      while (_queuedSize != null && mounted) {
        final size = _queuedSize!;
        _queuedSize = null;
        await NativeWindowService.setResizable(false, size: size);
        final center = await _windowCenter;
        if (mounted && center != null) {
          await windowManager.setPosition(
            center - Offset(size.width / 2, size.height / 2),
          );
        }
      }
    } on Object catch (error) {
      _queuedSize = null;
      if (mounted) debugPrint('Blue initialization resize: $error');
    }
  }

  Future<void> _finish() async {
    if (!_running || _finishing || !mounted) return;
    _finishing = true;
    if (widget.nativeWindow) {
      try {
        _queue(widget.targetSize);
        await _resizeDrain;
        if (!mounted) return;
        await NativeWindowService.setMinimumSize(widget.targetSize);
        await NativeWindowService.setResizable(
          widget.resizable,
          size: widget.targetSize,
        );
      } on Object catch (error) {
        debugPrint('Blue initialization resize: $error');
      }
    }
    if (!mounted) return;
    _progress.stop();
    widget.editorService?.setObscured(false, owner: 'blue-loading');
    setState(() => _running = false);
    widget.onCompleted();
  }

  @override
  void didUpdateWidget(BlueEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_running && oldWidget.editorService != widget.editorService) {
      oldWidget.editorService?.setObscured(false, owner: 'blue-loading');
      widget.editorService?.setObscured(true, owner: 'blue-loading');
    }
    if (_running && !widget.play) unawaited(_finish());
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _queuedSize = null;
    if (_running) {
      widget.editorService?.setObscured(false, owner: 'blue-loading');
    }
    _progress.dispose();
    _morph.dispose();
    _content.dispose();
    _secondary.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_running) return widget.child;
    return Semantics(
      label: 'Synapse initialization',
      liveRegion: true,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _progress,
          _morph,
          _content,
          _secondary,
          _exit,
        ]),
        builder: (context, _) => ColoredBox(
          color: widget.palette.color('initTheme.shellBg'),
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.cornerRadius),
              child: SizedBox(
                key: const ValueKey('blue-init-card'),
                width: 290 + 424 * _ease.transform(_morph.value),
                height: 355 + 38 * _ease.transform(_morph.value),
                child: Opacity(
                  opacity:
                      _ease.transform(_content.value) *
                      (1 - _ease.transform(_exit.value)),
                  child: BlueInitStage(
                    palette: widget.palette,
                    progress: _progress.value,
                    introOpacity: 1,
                    secondaryOpacity: _ease.transform(_secondary.value),
                    showStep: _progress.value > 0,
                    family: widget.family,
                    reducedMotion: widget.reducedMotion,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double blueProgressFill(double linear) {
  final t = linear.clamp(0.0, 1.0);
  final warped = math.min(1.0, t < 2 / 3 ? t : 2 / 3 + (t - 2 / 3) * 1.85);
  if (warped >= 1) return 1;
  final segment = (warped * 3).floor().clamp(0, 2);
  final u = warped * 3 - segment;
  return (segment + u * u * u) / 3;
}

class BlueInitStage extends StatelessWidget {
  const BlueInitStage({
    super.key,
    required this.palette,
    required this.progress,
    this.showStep = true,
    this.family = 'SynapseInter',
    this.reducedMotion = false,
    this.introOpacity = 1,
    this.secondaryOpacity = 1,
  });
  final BluePalette palette;
  final double progress;
  final bool showStep, reducedMotion;
  final String family;
  final double introOpacity, secondaryOpacity;
  static const steps = [
    (
      'Checking Status',
      'We are checking for an active\nPort Bridge connection to your executor.',
    ),
    (
      'Checking For Updates',
      'Run Port Bridge.lua in your executor to connect\nthe Port bridge.',
    ),
    (
      'Initialization Complete',
      'Thank you for your patience, enjoy using\nSynapse Framework',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final linear = progress.clamp(0.0, 1.0);
    final segment = (linear * 3).floor().clamp(0, 2);
    final fill = blueProgressFill(linear);
    TextStyle text(double size, {FontWeight weight = FontWeight.w400}) =>
        blueText(
          size,
          family: family,
          weight: weight,
          color: palette.color('initTheme.textPrimary'),
        );
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 128,
          child: Opacity(
            opacity: introOpacity,
            child: CustomPaint(painter: _InitHeaderPainter(palette)),
          ),
        ),
        Positioned(
          left: 10,
          top: 10,
          width: 208,
          height: 43,
          child: Opacity(
            opacity: introOpacity,
            child: Image.asset(
              'assets/synapse_blue/wordmark.png',
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
        Positioned(
          left: 10,
          top: 58,
          child: Opacity(
            opacity: introOpacity,
            child: Text("Let's get scripting.", style: text(20)),
          ),
        ),
        Positioned(
          left: 10,
          top: 119,
          child: Opacity(
            opacity: secondaryOpacity,
            child: Text('Initializing...', style: text(18)),
          ),
        ),
        Positioned(
          left: 10,
          top: 137,
          child: Opacity(
            opacity: secondaryOpacity,
            child: Text(
              "This won't take long.",
              style: text(
                13,
              ).copyWith(color: palette.color('initTheme.textSecondary')),
            ),
          ),
        ),
        Positioned(
          left: 8,
          top: 163,
          width: 20,
          height: 175,
          child: CustomPaint(painter: _InitProgressPainter(fill, palette)),
        ),
        if (showStep)
          AnimatedPositioned(
            duration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 550),
            curve: const Cubic(.4, 0, .2, 1),
            left: 36,
            top: 163 + segment * 51,
            width: 231,
            height: 56,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: palette.gradient(
                  'initTheme.stepPanelFrom',
                  'initTheme.stepPanelTo',
                ),
              ),
              child: AnimatedSwitcher(
                duration: reducedMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 280),
                switchInCurve: const Cubic(.4, 0, .2, 1),
                switchOutCurve: const Cubic(.4, 0, .2, 1),
                child: Stack(
                  key: ValueKey(segment),
                  children: [
                    Positioned(
                      left: 6,
                      top: 3,
                      right: 6,
                      child: Text(
                        steps[segment].$1,
                        style: text(
                          13,
                          weight: FontWeight.w900,
                        ).copyWith(height: 1.42),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      top: 20,
                      right: 6,
                      child: Text(
                        steps[segment].$2,
                        style: text(
                          9,
                          weight: FontWeight.w600,
                        ).copyWith(height: 1.42),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _InitHeaderPainter extends CustomPainter {
  const _InitHeaderPainter(this.palette);
  final BluePalette palette;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 290, 1);
    canvas.translate(-16.3, -5.3);
    final shadow = blueInitHeaderPath.shift(const Offset(0, 11));
    canvas.drawPath(
      shadow,
      Paint()
        ..color = const Color(0x69000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.15),
    );
    canvas.drawPath(
      blueInitHeaderPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.color('initTheme.headerFrom'),
            palette.color('initTheme.headerTo'),
          ],
          stops: const [0, .723454],
        ).createShader(const Rect.fromLTWH(16.3, 5.3, 290, 128)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InitHeaderPainter old) => old.palette != palette;
}

class _InitProgressPainter extends CustomPainter {
  const _InitProgressPainter(this.fill, this.palette);
  final double fill;
  final BluePalette palette;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      const Rect.fromLTWH(3, 7, 14, 160),
      Paint()..color = palette.color('initTheme.progressTrackBackground'),
    );
    canvas.drawRect(
      Rect.fromLTWH(3, 7, 14, 160 * math.max(fill, .001)),
      Paint()..color = palette.color('initTheme.progressBar'),
    );
    for (var i = 0; i < 4; i++) {
      final start = i == 3 ? .91 : i / 3;
      final raw = ((fill - start) / .09).clamp(0.0, 1.0);
      final color = Color.lerp(
        palette.color('initTheme.stepDotInactive'),
        palette.color('initTheme.stepDotActive'),
        1 - math.pow(1 - raw, 3).toDouble(),
      )!;
      final center = Offset(10, 10 + i * 51);
      canvas.drawCircle(center, 9.5, Paint()..color = color);
      canvas.drawCircle(
        center,
        9.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = palette.color('initTheme.stepDotStroke'),
      );
    }
  }

  @override
  bool shouldRepaint(_InitProgressPainter old) =>
      old.fill != fill || old.palette != palette;
}
