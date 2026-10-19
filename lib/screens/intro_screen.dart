import 'dart:async';

import 'package:flutter/material.dart';

import '../state/orion_controller.dart';
import '../theme/orion_theme.dart';
import '../theme/expressive_motion.dart';
import '../widgets/orion_logo.dart';

class IntroScreen extends StatefulWidget {
  final OrionController controller;
  final VoidCallback onComplete;
  final bool showcase;

  const IntroScreen({
    super.key,
    required this.controller,
    required this.onComplete,
    this.showcase = false,
  });

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(seconds: 3);
  late final AnimationController _timeline;
  late final Timer _completionTimer;
  bool _completed = false;
  bool _motionSuppressed = false;

  @override
  void initState() {
    super.initState();
    _timeline = AnimationController(
      vsync: this,
      duration: _duration,
      animationBehavior: AnimationBehavior.preserve,
    );
    _motionSuppressed = widget.controller.reducedMotion;
    widget.controller.addListener(_preferencesChanged);
    _completionTimer = Timer(_duration, _complete);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motionSuppressed = true;
      _timeline.stop();
    } else if (!_motionSuppressed && !_timeline.isAnimating && !_completed) {
      _timeline.forward();
    }
  }

  @override
  void didUpdateWidget(IntroScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_preferencesChanged);
      widget.controller.addListener(_preferencesChanged);
      _preferencesChanged();
    }
  }

  void _preferencesChanged() {
    if (widget.controller.reducedMotion) {
      // Once motion is disabled, keep the remainder of this brief intro still.
      _motionSuppressed = true;
      _timeline.stop();
    }
  }

  void _complete() {
    if (!mounted || _completed) return;
    _completed = true;
    _timeline.stop();
    widget.onComplete();
  }

  @override
  void dispose() {
    _completionTimer.cancel();
    widget.controller.removeListener(_preferencesChanged);
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, _timeline]),
    builder: (context, _) {
      final colors = OrionColors.of(context);
      final still =
          _motionSuppressed ||
          widget.controller.reducedMotion ||
          MediaQuery.disableAnimationsOf(context);
      double phase(double start, double end) =>
          ((_timeline.value - start) / (end - start)).clamp(0.0, 1.0);
      final logoFade = still
          ? 1.0
          : OrionMotion.effects.transform(phase(0, .13)).clamp(0.0, 1.0);
      final logoSettle = still
          ? 1.0
          : OrionMotion.spatial.transform(phase(0, .32));
      final title = still
          ? 1.0
          : OrionMotion.effects.transform(phase(.1, .34)).clamp(0.0, 1.0);
      final subtitle = still
          ? 1.0
          : OrionMotion.effects.transform(phase(.2, .44)).clamp(0.0, 1.0);
      final typeProgress = still
          ? 1.0
          : Curves.easeOutCubic.transform(phase(.04, .44));
      final exit = still
          ? 0.0
          : Curves.easeInCubic.transform(phase(2650 / 3000, 1));
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Opacity(
            opacity: 1 - exit,
            child: Transform.translate(
              offset: Offset(0, -7 * exit),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: logoFade,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - logoSettle)),
                      child: Transform.scale(
                        scale: .86 + .14 * logoSettle,
                        child: const OrionLogo(size: 108),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Opacity(
                    opacity: title,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - title)),
                      child: _typewriterText(
                        widget.showcase
                            ? 'Orion Expressive: Showcase'
                            : 'Orion Expressive',
                        typeProgress,
                        textAlign: TextAlign.center,
                        style: OrionType.pageTitle.copyWith(
                          fontSize: 32,
                          height: 1.25,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: subtitle,
                    child: Transform.translate(
                      offset: Offset(0, 8 * (1 - subtitle)),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: _typewriterText(
                          'Orion is back, this time under the Google material 3 expressive design language.',
                          typeProgress,
                          textAlign: TextAlign.center,
                          style: OrionType.body.copyWith(
                            fontSize: 14,
                            height: 1.5,
                            color: colors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _typewriterText(
    String text,
    double progress, {
    required TextAlign textAlign,
    required TextStyle style,
  }) {
    final codePoints = text.runes.toList(growable: false);
    final visibleCount = progress >= 1
        ? codePoints.length
        : (codePoints.length * progress).floor().clamp(0, codePoints.length);
    final visible = String.fromCharCodes(codePoints.take(visibleCount));
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: Text(visible, textAlign: textAlign, style: style),
      ),
    );
  }
}
