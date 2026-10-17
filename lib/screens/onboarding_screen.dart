import 'package:flutter/material.dart';

import '../state/orion_controller.dart';
import '../theme/expressive_motion.dart';
import '../theme/orion_theme.dart';
import '../widgets/orion_logo.dart';

/// A user-paced introduction. Completing and persisting the introduction is
/// owned by the shell; file dialogs and clipboard access are supplied by it.
class OrionOnboardingScreen extends StatefulWidget {
  const OrionOnboardingScreen({
    super.key,
    required this.controller,
    required this.onComplete,
    required this.onSaveBridge,
    required this.onCopyBridge,
    required this.onOpenBridgeFolder,
  });

  final OrionController controller;
  final VoidCallback onComplete;
  final Future<bool> Function() onSaveBridge;
  final Future<void> Function() onCopyBridge;
  final Future<void> Function() onOpenBridgeFolder;

  @override
  State<OrionOnboardingScreen> createState() => _OrionOnboardingScreenState();
}

enum _BridgeAction { save, copy, folder }

class _OrionOnboardingScreenState extends State<OrionOnboardingScreen>
    with SingleTickerProviderStateMixin {
  static const _stepCount = 4;
  static const _transitionDuration = Duration(milliseconds: 540);
  late final AnimationController _pageMotion;
  int _step = 0;
  int? _outgoingStep;
  List<Widget>? _incomingParts, _outgoingParts;
  final _viewportKeys = List.generate(
    _stepCount,
    (index) => GlobalKey(debugLabel: 'onboarding-step-$index'),
  );
  double _outgoingPartProgress = 1, _outgoingOpacity = 1;
  Offset _outgoingOffset = Offset.zero;
  double _progressFrom = 1;
  bool _goingBack = false;
  bool _completed = false;
  _BridgeAction? _busy;
  String? _feedback;
  bool _actionFailed = false;

  bool get _busyOrCompleted => _busy != null || _completed;
  bool get _still =>
      widget.controller.reducedMotion ||
      MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _pageMotion = AnimationController(
      vsync: this,
      duration: _transitionDuration,
      value: 1,
    )..addStatusListener(_motionStatus);
    widget.controller.addListener(_motionPreferenceChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionPreferenceChanged();
  }

  @override
  void didUpdateWidget(OrionOnboardingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_motionPreferenceChanged);
      widget.controller.addListener(_motionPreferenceChanged);
      _motionPreferenceChanged();
    }
  }

  void _motionStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _outgoingStep != null) {
      setState(() {
        _outgoingStep = null;
        _outgoingParts = null;
      });
    }
  }

  void _motionPreferenceChanged() {
    if (_still && _pageMotion.isAnimating) {
      _pageMotion.stop();
      _pageMotion.value = 1;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_motionPreferenceChanged);
    _pageMotion
      ..removeStatusListener(_motionStatus)
      ..dispose();
    super.dispose();
  }

  static double _phase(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);

  double get _progress =>
      _progressFrom +
      (_step + 1 - _progressFrom) *
          Curves.easeInOutCubicEmphasized.transform(
            _phase(_pageMotion.value, .08, .86),
          );

  void _next() {
    if (_busyOrCompleted) return;
    if (_step == _stepCount - 1) {
      setState(() => _completed = true);
      widget.onComplete();
      return;
    }
    _moveTo(_step + 1);
  }

  void _moveTo(int step) {
    if (_busyOrCompleted || step < 0 || step >= _stepCount) return;
    final progress = _progress;
    // A quick reversal brings back the page still on screen, rather than
    // accumulating half-visible pages or flashing a page that never entered.
    final t = _pageMotion.value;
    final moving = _outgoingStep != null;
    final previous = t < .24 ? _outgoingStep ?? _step : _step;
    final keepOutgoing = moving && previous == _outgoingStep;
    final direction = _goingBack ? -1.0 : 1.0;
    final exit = Curves.easeOutCubic.transform(_phase(t, 0, .24));
    final arrive = OrionMotion.spatial.transform(_phase(t, .16, 1));
    final parts = keepOutgoing ? _outgoingParts : _incomingParts;
    final partProgress = keepOutgoing
        ? _outgoingPartProgress
        : moving
        ? t
        : 1.0;
    final opacity = keepOutgoing ? _outgoingOpacity * (1 - exit) : 1.0;
    final offset = keepOutgoing
        ? _outgoingOffset + Offset(-direction * 22 * exit, -3 * exit)
        : moving
        ? Offset(direction * 38 * (1 - arrive), 0)
        : Offset.zero;
    _pageMotion.stop();
    setState(() {
      _goingBack = step < _step;
      _outgoingStep = previous == step ? null : previous;
      // Freeze the visible content, including setup feedback and the current
      // entrance pose. Retargeting cannot brighten it or re-centre its text.
      _outgoingParts = parts;
      _outgoingPartProgress = partProgress;
      _outgoingOpacity = opacity;
      _outgoingOffset = offset;
      _progressFrom = progress;
      _step = step;
      _feedback = null;
      _actionFailed = false;
    });
    if (_still || _outgoingStep == null) {
      _outgoingStep = null;
      _outgoingParts = null;
      _pageMotion.value = 1;
    } else {
      _pageMotion.forward(from: 0);
    }
  }

  Future<void> _perform(_BridgeAction action) async {
    if (_busyOrCompleted) return;
    setState(() {
      _busy = action;
      _feedback = null;
      _actionFailed = false;
    });
    String? feedback;
    var failed = false;
    try {
      switch (action) {
        case _BridgeAction.save:
          if (await widget.onSaveBridge()) {
            feedback =
                'Bridge script saved. Keep it in your executor’s autoexecute folder.';
          }
        case _BridgeAction.copy:
          await widget.onCopyBridge();
          feedback = 'Bridge script copied.';
        case _BridgeAction.folder:
          await widget.onOpenBridgeFolder();
          feedback = 'Bridge folder opened.';
      }
    } catch (_) {
      failed = true;
      feedback = switch (action) {
        _BridgeAction.save => 'Couldn’t save the Bridge script. Try again.',
        _BridgeAction.copy => 'Couldn’t copy the Bridge script. Try again.',
        _BridgeAction.folder => 'Couldn’t open the Bridge folder. Try again.',
      };
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      _feedback = feedback;
      _actionFailed = failed;
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final colors = OrionColors.of(context);
      return FocusTraversalGroup(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 430 || constraints.maxWidth < 560;
            final edge = compact ? 20.0 : 36.0;
            return Padding(
              padding: EdgeInsets.fromLTRB(edge, compact ? 12 : 24, edge, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Getting started',
                            style: OrionType.label.copyWith(color: colors.ink),
                          ),
                          const Spacer(),
                          Semantics(
                            label: 'Step ${_step + 1} of $_stepCount',
                            child: ExcludeSemantics(
                              child: Text(
                                '${_step + 1} of $_stepCount',
                                style: OrionType.metadata.copyWith(
                                  color: colors.muted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AnimatedBuilder(
                        animation: _pageMotion,
                        builder: (context, _) => Row(
                          children: [
                            for (
                              var index = 0;
                              index < _stepCount;
                              index++
                            ) ...[
                              if (index != 0) const SizedBox(width: 5),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: SizedBox(
                                    height: 4,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        ColoredBox(
                                          color: colors.stateFill(.12),
                                        ),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: FractionallySizedBox(
                                            key: ValueKey(
                                              'onboarding-progress-$index',
                                            ),
                                            widthFactor: (_progress - index)
                                                .clamp(0.0, 1.0),
                                            heightFactor: 1,
                                            child: ColoredBox(
                                              color: colors.readableAccent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, bodyConstraints) => _stage(
                            colors,
                            compact,
                            bodyConstraints.maxHeight,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (_step > 0)
                            TextButton.icon(
                              key: const ValueKey('onboarding-back'),
                              onPressed: _busyOrCompleted
                                  ? null
                                  : () => _moveTo(_step - 1),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                size: 17,
                              ),
                              label: const Text('Back'),
                            ),
                          const Spacer(),
                          SizedBox(
                            width: 124,
                            child: FilledButton.icon(
                              key: const ValueKey('onboarding-next'),
                              onPressed: _busyOrCompleted ? null : _next,
                              icon: Icon(
                                _step == _stepCount - 1
                                    ? Icons.arrow_outward_rounded
                                    : Icons.arrow_forward_rounded,
                                size: 17,
                              ),
                              iconAlignment: IconAlignment.end,
                              label: Text(
                                _step == _stepCount - 1
                                    ? 'Open Orion'
                                    : 'Continue',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );

  Widget _stage(OrionColors colors, bool compact, double height) {
    final moving = _outgoingStep != null;
    // Build and lay out the page content once per state/theme/size change.
    // Frame callbacks only update its surrounding paint and input transforms.
    final outgoing = _outgoingStep == null
        ? null
        : _pageViewport(
            _outgoingStep!,
            colors,
            compact,
            height,
            frozenParts: _outgoingParts,
            partProgress: _outgoingPartProgress,
          );
    final incoming = _pageViewport(
      _step,
      colors,
      compact,
      height,
      animateParts: moving,
    );
    return AnimatedBuilder(
      animation: _pageMotion,
      builder: (context, _) {
        final t = moving ? _pageMotion.value : 1.0;
        final direction = _goingBack ? -1.0 : 1.0;
        final exit = Curves.easeOutCubic.transform(_phase(t, 0, .24));
        final arrive = OrionMotion.spatial.transform(_phase(t, .16, 1));
        return ClipRect(
          key: const ValueKey('onboarding-page-stage'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (outgoing != null)
                ExcludeFocus(
                  key: const ValueKey('onboarding-outgoing-page'),
                  child: ExcludeSemantics(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: _outgoingOpacity * (1 - exit),
                        child: Transform.translate(
                          offset:
                              _outgoingOffset +
                              Offset(-direction * 22 * exit, -3 * exit),
                          child: outgoing,
                        ),
                      ),
                    ),
                  ),
                ),
              ExcludeFocus(
                key: const ValueKey('onboarding-incoming-page'),
                excluding: moving && t < .36,
                child: IgnorePointer(
                  ignoring: moving && t < .36,
                  child: Transform.translate(
                    offset: Offset(direction * 38 * (1 - arrive), 0),
                    child: incoming,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pageViewport(
    int step,
    OrionColors colors,
    bool compact,
    double height, {
    bool animateParts = false,
    List<Widget>? frozenParts,
    double? partProgress,
  }) => SingleChildScrollView(
    // Reparent the scrolling viewport as it leaves, preserving its exact
    // position on smaller windows instead of jumping back to the first line.
    key: _viewportKeys[step],
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 20 : 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SizedBox(
              width: double.infinity,
              child: _page(
                step,
                colors,
                compact,
                animateParts: animateParts,
                frozenParts: frozenParts,
                partProgress: partProgress,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _page(
    int step,
    OrionColors colors,
    bool compact, {
    bool animateParts = false,
    List<Widget>? frozenParts,
    double? partProgress,
  }) {
    var part = 0;
    final children = frozenParts ?? _pageChildren(step, colors, compact);
    if (step == _step) _incomingParts = children;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final child in children)
          if (child is SizedBox)
            child
          else
            _part(child, step, part++, animateParts, partProgress),
      ],
    );
  }

  Widget _part(
    Widget child,
    int step,
    int index,
    bool animated,
    double? progress,
  ) {
    Widget pose(Widget content, double t) {
      final start = .18 + index.clamp(0, 5) * .045;
      final fade = Curves.easeOutCubic.transform(_phase(t, start, start + .24));
      final settle = OrionMotion.spatial.transform(_phase(t, start, 1));
      return Opacity(
        key: ValueKey('onboarding-part-$step-$index'),
        opacity: fade,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - settle)),
          child: content,
        ),
      );
    }

    if (progress != null || !animated) return pose(child, progress ?? 1.0);
    return AnimatedBuilder(
      animation: _pageMotion,
      child: child,
      builder: (context, content) => pose(content!, _pageMotion.value),
    );
  }

  List<Widget> _pageChildren(
    int step,
    OrionColors colors,
    bool compact,
  ) => switch (step) {
    0 => [
      Padding(
        padding: EdgeInsets.only(bottom: compact ? 24 : 34),
        child: OrionWordmark(
          height: compact ? 43 : 56,
          customImage: widget.controller.customLogoBytes,
        ),
      ),
      _heading('Welcome to Orion', colors, compact),
      const SizedBox(height: 10),
      _description(
        'A quick setup for your executor. Then, straight to your workspace.',
        colors,
      ),
    ],
    1 => [
      _heading('Connect your executor', colors, compact),
      const SizedBox(height: 10),
      _description(
        'Place Orion Bridge.lua in your executor’s autoexecute folder '
        'so it runs automatically. To connect now, run it once.',
        colors,
      ),
      const SizedBox(height: 18),
      _bridgeFile(colors),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('onboarding-save-bridge'),
            onPressed: _busyOrCompleted
                ? null
                : () => _perform(_BridgeAction.save),
            icon: _actionIcon(_BridgeAction.save, Icons.save_alt_rounded),
            label: const Text('Save script'),
          ),
          TextButton.icon(
            key: const ValueKey('onboarding-copy-bridge'),
            onPressed: _busyOrCompleted
                ? null
                : () => _perform(_BridgeAction.copy),
            icon: _actionIcon(_BridgeAction.copy, Icons.content_copy_rounded),
            label: const Text('Copy script'),
          ),
          TextButton.icon(
            key: const ValueKey('onboarding-open-bridge-folder'),
            onPressed: _busyOrCompleted
                ? null
                : () => _perform(_BridgeAction.folder),
            icon: _actionIcon(_BridgeAction.folder, Icons.folder_open_rounded),
            label: const Text('Open folder'),
          ),
        ],
      ),
      if (_feedback != null) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  _actionFailed
                      ? Icons.info_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 16,
                  color: colors.readableAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _feedback!,
                  key: const ValueKey('onboarding-feedback'),
                  style: OrionType.label.copyWith(
                    color: colors.ink,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ],
    2 => [
      _symbol(Icons.bolt_rounded, colors, compact),
      const SizedBox(height: 18),
      _heading('Smoother starts', colors, compact),
      const SizedBox(height: 12),
      _badge('Recommended', colors),
      const SizedBox(height: 14),
      _description(
        'Turn on auto attach in your executor’s settings, if available. '
        'It helps the executor attach to Roblox automatically.',
        colors,
      ),
    ],
    _ => [
      _symbol(Icons.rocket_launch_rounded, colors, compact),
      const SizedBox(height: 18),
      _heading('Executor Quick Launch', colors, compact),
      const SizedBox(height: 12),
      _badge('Coming soon', colors),
      const SizedBox(height: 14),
      _description(
        'Automatically launch your chosen executor with Orion. '
        'Quick Launch is coming in a future update.',
        colors,
      ),
      const SizedBox(height: 18),
      _description('You’re ready to make Orion yours.', colors),
    ],
  };

  Widget _heading(String text, OrionColors colors, bool compact) => Text(
    text,
    style: OrionType.pageTitle.copyWith(
      fontSize: compact ? 26 : 30,
      color: colors.ink,
    ),
  );

  Widget _description(String text, OrionColors colors) => Text(
    text,
    style: OrionType.body.copyWith(fontSize: 14, color: colors.muted),
  );

  BorderRadius _shape(OrionColors colors, double radius) => BorderRadius.only(
    topLeft: Radius.circular(radius),
    topRight: Radius.circular(radius),
    bottomLeft: Radius.circular(radius),
    bottomRight: Radius.circular(colors.glassEnabled ? radius : 8),
  );

  Widget _symbol(IconData icon, OrionColors colors, bool compact) => Container(
    width: compact ? 54 : 64,
    height: compact ? 54 : 64,
    decoration: BoxDecoration(
      color: colors.stateFill(.12),
      borderRadius: _shape(colors, compact ? 20 : 24),
    ),
    child: Icon(icon, size: compact ? 28 : 32, color: colors.readableAccent),
  );

  Widget _badge(String text, OrionColors colors) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: colors.stateFill(.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: OrionType.metadata.copyWith(
        fontWeight: FontWeight.w600,
        color: colors.readableAccent,
      ),
    ),
  );

  Widget _bridgeFile(OrionColors colors) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: colors.chrome(colors.panel, role: 'panel'),
      border: Border.all(color: colors.outline(.55)),
      borderRadius: _shape(colors, 22),
    ),
    child: Row(
      children: [
        Icon(
          Icons.description_outlined,
          size: 24,
          color: colors.readableAccent,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Orion Bridge.lua',
                style: OrionType.body.copyWith(
                  color: colors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Your executor → autoexecute',
                style: OrionType.metadata.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _actionIcon(_BridgeAction action, IconData icon) => _busy == action
      ? const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(icon, size: 17);
}
