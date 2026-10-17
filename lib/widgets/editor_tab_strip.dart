import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/orion_theme.dart';

/// A desktop tab viewport. The wheel pans the strip, never changes documents.
class EditorTabStrip extends StatefulWidget {
  const EditorTabStrip({
    super.key,
    required this.tabIds,
    required this.activeId,
    required this.tabBuilder,
    required this.colors,
    required this.reducedMotion,
    this.compact = false,
  });

  final List<String> tabIds;
  final String activeId;
  final IndexedWidgetBuilder tabBuilder;
  final OrionColors colors;
  final bool reducedMotion, compact;

  @override
  State<EditorTabStrip> createState() => _EditorTabStripState();
}

class _EditorTabStripState extends State<EditorTabStrip> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _tabs = <String, GlobalKey>{};
  bool _overflow = false, _back = false, _forward = false;
  bool _queued = false, _revealRequested = true;
  double _width = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_queueRefresh);
  }

  @override
  void didUpdateWidget(EditorTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedTabs = !listEquals(oldWidget.tabIds, widget.tabIds);
    if (changedTabs) {
      final ids = widget.tabIds.toSet();
      _tabs.removeWhere((id, _) => !ids.contains(id));
    }
    if (oldWidget.activeId != widget.activeId) {
      _queueRefresh(reveal: true);
    } else if (changedTabs) {
      _queueRefresh(reveal: _activeInView);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _queueRefresh({bool reveal = false}) {
    _revealRequested |= reveal;
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (!position.hasContentDimensions) return;
      // Compare with the entire available width, including any cue buttons.
      // This lets the cues disappear as soon as all tabs fit after a resize.
      final overflow =
          position.maxScrollExtent > .5 &&
          position.viewportDimension + position.maxScrollExtent > _width + .5;
      final back = position.pixels > position.minScrollExtent + .5;
      final forward = position.pixels < position.maxScrollExtent - .5;
      final changedLayout = overflow != _overflow;
      if (changedLayout || back != _back || forward != _forward) {
        setState(() {
          _overflow = overflow;
          _back = back;
          _forward = forward;
        });
      }
      if (changedLayout) {
        // Measure the selected tab after the cue buttons take their space.
        _queueRefresh(reveal: _activeInView);
      } else if (_revealRequested) {
        _revealRequested = false;
        _revealActive();
      }
    });
  }

  void _moveTo(double offset) {
    final position = _scroll.position;
    final target = offset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < .5) return;
    if (widget.reducedMotion) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  ({Rect rect, double width})? get _activeBounds {
    final tab = _tabs[widget.activeId]?.currentContext?.findRenderObject();
    final viewport = _viewport.currentContext?.findRenderObject();
    if (tab is! RenderBox ||
        viewport is! RenderBox ||
        !tab.attached ||
        !viewport.attached ||
        !tab.hasSize ||
        !viewport.hasSize) {
      return null;
    }
    final rect = MatrixUtils.transformRect(
      tab.getTransformTo(viewport),
      Offset.zero & tab.size,
    );
    return (rect: rect, width: viewport.size.width);
  }

  bool get _activeInView {
    final bounds = _activeBounds;
    return bounds != null &&
        bounds.rect.right > 0 &&
        bounds.rect.left < bounds.width;
  }

  void _revealActive() {
    final bounds = _activeBounds;
    if (bounds == null) return;
    final rect = bounds.rect;
    final delta = rect.left < 0
        ? rect.left
        : rect.right > bounds.width
        ? rect.right - bounds.width
        : 0.0;
    final direction = _scroll.position.axisDirection == AxisDirection.left
        ? -1
        : 1;
    _moveTo(_scroll.offset + delta * direction);
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dx != 0 ||
        event.scrollDelta.dy == 0 ||
        !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    if (!position.hasContentDimensions ||
        !position.physics.shouldAcceptUserOffset(position)) {
      return;
    }
    final delta =
        event.scrollDelta.dy *
        (position.axisDirection == AxisDirection.left ? -1 : 1);
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    // The inner Scrollable gets first refusal for horizontal/Shift-wheel input.
    // At either edge leave the signal available to an enclosing scroll view.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.position.pointerScroll(delta);
      event.respond(allowPlatformDefault: false);
    });
  }

  Widget _cue({required bool back}) {
    final enabled = back ? _back : _forward;
    final colors = widget.colors;
    final extent = widget.compact ? 22.0 : 24.0;
    return IconButton(
      key: ValueKey(back ? 'editor-tabs-back' : 'editor-tabs-forward'),
      tooltip: back ? 'Scroll tabs left' : 'Scroll tabs right',
      onPressed: !enabled
          ? null
          : () => _moveTo(
              _scroll.offset +
                  (back ? -1 : 1) * _scroll.position.viewportDimension * .72,
            ),
      style: IconButton.styleFrom(
        minimumSize: Size.square(extent),
        maximumSize: Size.square(extent),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: colors.readableAccent,
        disabledForegroundColor: colors.muted.withValues(alpha: .3),
        backgroundColor: colors.stateFill(.065),
        disabledBackgroundColor: colors.stateFill(.025),
        hoverColor: colors.stateFill(.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(back ? 10 : 4),
            right: Radius.circular(back ? 4 : 10),
          ),
        ),
      ),
      icon: Icon(
        back ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
        size: 17,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_width != constraints.maxWidth) {
          _width = constraints.maxWidth;
          _queueRefresh(reveal: true);
        }
        return Listener(
          onPointerSignal: _wheel,
          child: Row(
            children: [
              if (_overflow) ...[_cue(back: true), const SizedBox(width: 3)],
              Expanded(
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: (_) {
                    _queueRefresh(reveal: _activeInView);
                    return false;
                  },
                  child: ClipRect(
                    key: _viewport,
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        key: const ValueKey('editor-tab-scroll'),
                        controller: _scroll,
                        primary: false,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final (index, id) in widget.tabIds.indexed)
                              KeyedSubtree(
                                key: ValueKey('editor-tab:$id'),
                                child: KeyedSubtree(
                                  key: _tabs.putIfAbsent(id, GlobalKey.new),
                                  child: widget.tabBuilder(context, index),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_overflow) ...[const SizedBox(width: 3), _cue(back: false)],
            ],
          ),
        );
      },
    );
  }
}
