import 'package:flutter/material.dart';
import '../theme/expressive_motion.dart';

/// A short, damped press response that leaves layout and hit targets fixed.
class SpringPressFeedback extends StatefulWidget {
  const SpringPressFeedback({
    super.key,
    required this.child,
    required this.reducedMotion,
    this.enabled = true,
  });

  final Widget child;
  final bool reducedMotion;
  final bool enabled;

  @override
  State<SpringPressFeedback> createState() => _SpringPressFeedbackState();
}

class _SpringPressFeedbackState extends State<SpringPressFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  final _pointers = <int>{};
  void _respond() {
    if (widget.reducedMotion || !widget.enabled) return;
    _scale.animateTo(
      _pointers.isEmpty ? 1 : .985,
      duration: const Duration(milliseconds: 300),
      curve: OrionMotion.spatialFast,
    );
  }

  @override
  void didUpdateWidget(SpringPressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reducedMotion || !widget.enabled) {
      _scale.stop();
      _scale.value = 1;
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      _pointers.add(event.pointer);
      _respond();
    },
    onPointerUp: (event) {
      _pointers.remove(event.pointer);
      _respond();
    },
    onPointerCancel: (event) {
      _pointers.remove(event.pointer);
      _respond();
    },
    child: AnimatedBuilder(
      animation: _scale,
      child: widget.child,
      builder: (context, child) => Transform.scale(
        scale: _scale.value.clamp(.98, 1.005),
        transformHitTests: false,
        child: child,
      ),
    ),
  );
}

/// Connected controls have rounded group ends and short internal corners.
/// Each action keeps its own ink response, focus target and semantics.
class ConnectedActionGroup extends StatelessWidget {
  const ConnectedActionGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(width: 1),
          children[index],
        ],
      ],
    ),
  );
}

WidgetStateProperty<OutlinedBorder> connectedActionShape({
  required int index,
  required int count,
  required bool reducedMotion,
  double radius = 12,
  bool asymmetric = false,
}) => WidgetStateProperty.resolveWith((states) {
  final pressed = !reducedMotion && states.contains(WidgetState.pressed);
  final hovered = !reducedMotion && states.contains(WidgetState.hovered);
  final outer = pressed ? radius * .85 : radius;
  final inner = pressed
      ? 6.0
      : hovered
      ? 5.0
      : 3.0;
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(index == 0 ? outer : inner),
      bottomLeft: Radius.circular(index == 0 && !asymmetric ? outer : inner),
      topRight: Radius.circular(
        index == count - 1 && !asymmetric ? outer : inner,
      ),
      bottomRight: Radius.circular(index == count - 1 ? outer : inner),
    ),
  );
});
