import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/orion_controller.dart';
import '../theme/expressive_motion.dart';
import '../theme/orion_theme.dart';
import 'orion_logo.dart';

/// A single, finite reveal over the already mounted main Orion interface.
///
/// The host owns when this runs and keeps native editor content obscured until
/// [onComplete]. This widget only owns the visual cover and its input barrier.
class OrionStartupReveal extends StatefulWidget {
  static const duration = Duration(milliseconds: 950);

  final OrionController controller;
  final VoidCallback onComplete;

  const OrionStartupReveal({
    super.key,
    required this.controller,
    required this.onComplete,
  });

  @override
  State<OrionStartupReveal> createState() => _OrionStartupRevealState();
}

class _OrionStartupRevealState extends State<OrionStartupReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _timeline;
  late final Timer _deadline;
  bool _completed = false;
  bool _completionScheduled = false;

  @override
  void initState() {
    super.initState();
    _timeline = AnimationController(
      vsync: this,
      duration: OrionStartupReveal.duration,
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener(_animationStatus);
    // Keep launch time bounded even when the app loses focus before the last
    // animation frame or the host temporarily mutes tickers.
    _deadline = Timer(OrionStartupReveal.duration, _complete);
    widget.controller.addListener(_preferencesChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _synchronizeMotion();
  }

  @override
  void didUpdateWidget(OrionStartupReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_preferencesChanged);
      widget.controller.addListener(_preferencesChanged);
      _synchronizeMotion();
    }
  }

  void _preferencesChanged() {
    if (!mounted) return;
    _synchronizeMotion();
  }

  void _synchronizeMotion() {
    if (_completed || _completionScheduled) return;
    if (widget.controller.reducedMotion ||
        MediaQuery.disableAnimationsOf(context)) {
      _timeline.stop();
      // Completion may remove the overlay from its parent's tree. Defer that
      // mutation until the current build/layout pass has finished.
      _completionScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
    } else if (!_timeline.isAnimating) {
      _timeline.forward();
    }
  }

  void _animationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _complete();
  }

  void _complete() {
    if (!mounted || _completed) return;
    _completed = true;
    _deadline.cancel();
    _timeline
      ..stop()
      ..value = 1;
    widget.onComplete();
  }

  @override
  void dispose() {
    _deadline.cancel();
    widget.controller.removeListener(_preferencesChanged);
    _timeline
      ..removeStatusListener(_animationStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AbsorbPointer(
      child: ClipRect(
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final colors = OrionColors.of(context);
            final still =
                widget.controller.reducedMotion ||
                MediaQuery.disableAnimationsOf(context);
            return LayoutBuilder(
              builder: (context, constraints) {
                final height = constraints.maxHeight;
                // The cropped wordmark includes a wide custom logo too. Its
                // proportions stay constant as the host window gets compact.
                final logoHeight = math.min(54.0, constraints.maxWidth / 7.2);
                return AnimatedBuilder(
                  animation: _timeline,
                  // Only its surrounding pose changes on a frame. Retain the
                  // decoded logo widget and its existing isolated paint layer.
                  child: RepaintBoundary(
                    child: OrionWordmark(
                      height: logoHeight,
                      customImage: widget.controller.customLogoBytes,
                    ),
                  ),
                  builder: (context, logo) {
                    double phase(double start, double end) =>
                        ((_timeline.value - start) / (end - start)).clamp(
                          0.0,
                          1.0,
                        );
                    final arrival = still
                        ? 1.0
                        : OrionMotion.effects
                              .transform(phase(0, .22))
                              .clamp(0.0, 1.0);
                    final settle = still
                        ? 1.0
                        : OrionMotion.spatial.transform(phase(0, .29));
                    final departure = still
                        ? 0.0
                        : Curves.easeInOutCubic.transform(phase(.33, .77));
                    final uncover = still
                        ? 0.0
                        : Curves.easeInOutCubicEmphasized.transform(
                            phase(.51, 1),
                          );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Transform.translate(
                          key: const ValueKey('orion-startup-cover'),
                          offset: Offset(0, -(height + 1) * uncover),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.background,
                              gradient: colors.backgroundGradient,
                              // A sheet edge appears only as the cover leaves.
                              // The asymmetric finish echoes the main shell.
                              borderRadius: BorderRadius.only(
                                bottomRight: Radius.circular(32 * uncover),
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: Transform.translate(
                            key: const ValueKey('orion-startup-logo'),
                            offset: Offset(
                              0,
                              14 * (1 - settle) -
                                  (height / 2 + logoHeight + 24) * departure,
                            ),
                            child: Opacity(
                              opacity: arrival,
                              child: Transform.scale(
                                scale: .94 + .06 * settle,
                                child: logo,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    ),
  );
}
