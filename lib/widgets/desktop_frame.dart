import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../services/native_window_service.dart';
import '../theme/orion_theme.dart';

/// Clips every route, including dialogs, to the native window's curved frame.
class DesktopFrame extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final bool reducedMotion;
  final double cornerRadius;
  final Color? borderColor;
  final bool syncNativeCorners;
  const DesktopFrame({
    super.key,
    required this.child,
    required this.enabled,
    required this.reducedMotion,
    this.cornerRadius = 16,
    this.borderColor,
    this.syncNativeCorners = false,
  });
  @override
  State<DesktopFrame> createState() => _DesktopFrameState();
}

class _DesktopFrameState extends State<DesktopFrame> with WindowListener {
  // Native curve/resize modes reparent the foreground without resetting the
  // Navigator, editor, focus or page state held inside this frame.
  final _foreground = GlobalKey();
  bool _maximized = false;
  int _stateRequest = 0;
  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      windowManager.addListener(this);
      _readWindowState();
      if (widget.syncNativeCorners) unawaited(_syncNativeCorners());
    }
  }

  Future<void> _readWindowState() async {
    final request = ++_stateRequest;
    final values = await Future.wait([
      windowManager.isMaximized(),
      windowManager.isFullScreen(),
    ]);
    if (mounted && request == _stateRequest) {
      setState(() => _maximized = values.any((value) => value));
    }
  }

  Future<void> _syncNativeCorners() => NativeWindowService.setCornerRadius(
    widget.enabled && widget.syncNativeCorners ? widget.cornerRadius : 0,
  );

  @override
  void didUpdateWidget(DesktopFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        windowManager.addListener(this);
        unawaited(_readWindowState());
      } else {
        windowManager.removeListener(this);
      }
    }
    if ((oldWidget.syncNativeCorners || widget.syncNativeCorners) &&
        (oldWidget.enabled != widget.enabled ||
            oldWidget.syncNativeCorners != widget.syncNativeCorners ||
            oldWidget.cornerRadius != widget.cornerRadius)) {
      unawaited(_syncNativeCorners());
    }
  }

  void _expanded() {
    _stateRequest++;
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowMaximize() => _expanded();
  @override
  void onWindowUnmaximize() => unawaited(_readWindowState());
  @override
  void onWindowEnterFullScreen() => _expanded();
  @override
  void onWindowLeaveFullScreen() => _readWindowState();
  @override
  void dispose() {
    if (widget.enabled) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(key: _foreground, child: widget.child);
    if (!widget.enabled) return content;
    final colors = OrionColors.of(context);
    final radius = _maximized ? 0.0 : widget.cornerRadius;
    final frame = AnimatedContainer(
      duration: widget.reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      // Compose overlapping opaque backdrops/lenses before applying edge
      // coverage. Per-draw AA otherwise blends already-covered colors into
      // the curve, creating a jagged pale fringe at translucent window edges.
      // Keep the existing source-window paint path unchanged.
      clipBehavior: widget.syncNativeCorners && radius > 0
          ? Clip.antiAliasWithSaveLayer
          : Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius)),
      foregroundDecoration: colors.glassEnabled
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: widget.borderColor ?? colors.outline(.65),
              ),
            ),
      child: widget.syncNativeCorners
          ? _CurvedResizeArea(
              enabled: !_maximized,
              radius: radius,
              child: content,
            )
          : content,
    );
    if (widget.syncNativeCorners) return frame;
    return DragToResizeArea(
      resizeEdgeSize: 5,
      enableResizeEdges: _maximized ? const [] : null,
      child: frame,
    );
  }
}

/// A five-pixel perimeter follows the visible arc. Square corner handles would
/// sit entirely outside a 20px curve, making diagonal resizing unreachable.
class _CurvedResizeArea extends StatelessWidget {
  const _CurvedResizeArea({
    required this.enabled,
    required this.radius,
    required this.child,
  });
  final bool enabled;
  final double radius;
  final Widget child;
  static const edgeSize = 5.0;

  Widget _handle(ResizeEdge edge, MouseCursor cursor) => MouseRegion(
    cursor: cursor,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startResizing(edge),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final corner = radius < edgeSize ? edgeSize : radius;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          top: 0,
          left: corner,
          right: corner,
          height: edgeSize,
          child: _handle(ResizeEdge.top, SystemMouseCursors.resizeUp),
        ),
        Positioned(
          bottom: 0,
          left: corner,
          right: corner,
          height: edgeSize,
          child: _handle(ResizeEdge.bottom, SystemMouseCursors.resizeDown),
        ),
        Positioned(
          left: 0,
          top: corner,
          bottom: corner,
          width: edgeSize,
          child: _handle(ResizeEdge.left, SystemMouseCursors.resizeLeft),
        ),
        Positioned(
          right: 0,
          top: corner,
          bottom: corner,
          width: edgeSize,
          child: _handle(ResizeEdge.right, SystemMouseCursors.resizeRight),
        ),
        for (final (alignment, edge, cursor) in const [
          (
            Alignment.topLeft,
            ResizeEdge.topLeft,
            SystemMouseCursors.resizeUpLeft,
          ),
          (
            Alignment.topRight,
            ResizeEdge.topRight,
            SystemMouseCursors.resizeUpRight,
          ),
          (
            Alignment.bottomLeft,
            ResizeEdge.bottomLeft,
            SystemMouseCursors.resizeDownLeft,
          ),
          (
            Alignment.bottomRight,
            ResizeEdge.bottomRight,
            SystemMouseCursors.resizeDownRight,
          ),
        ])
          Positioned(
            top: alignment.y < 0 ? 0 : null,
            bottom: alignment.y > 0 ? 0 : null,
            left: alignment.x < 0 ? 0 : null,
            right: alignment.x > 0 ? 0 : null,
            width: corner,
            height: corner,
            child: ClipPath(
              clipper: _ResizeArcClipper(alignment, radius, edgeSize),
              child: _handle(edge, cursor),
            ),
          ),
      ],
    );
  }
}

class _ResizeArcClipper extends CustomClipper<Path> {
  const _ResizeArcClipper(this.alignment, this.radius, this.thickness);
  final Alignment alignment;
  final double radius, thickness;

  @override
  Path getClip(Size size) {
    if (radius <= thickness) return Path()..addRect(Offset.zero & size);
    final center = Offset(
      alignment.x < 0 ? size.width : 0,
      alignment.y < 0 ? size.height : 0,
    );
    final outside = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final inside = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius - thickness));
    return Path.combine(
      PathOperation.intersect,
      Path.combine(PathOperation.difference, outside, inside),
      Path()..addRect(Offset.zero & size),
    );
  }

  @override
  bool shouldReclip(_ResizeArcClipper oldClipper) =>
      oldClipper.alignment != alignment ||
      oldClipper.radius != radius ||
      oldClipper.thickness != thickness;
}
